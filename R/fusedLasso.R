#' Generalized fused lasso to partition cell types by allelic imbalance
#'
#' Fits generalized fused lasso with either binomial(link="logit")
#' or Gaussian likelihood, leveraging functions from the
#' \code{smurf} package.
#'
#' @param sce A SingleCellExperiment containing assays (\code{"ratio"},
#' \code{"counts"}) and colData \code{"x"}
#' @param formula A \code{\link[stats]{formula}} object which will typically
#' involve a fused lasso penalty: default is just using cell-type `x`:
#' \code{ratio ~ p(x, pen="gflasso")}. Other possibilities would be to use
#' the Graph-Guided Fused Lasso penalty, or add covariates want to be
#' adjusted for, which can include a gene-level baseline `gene`
#' \code{ratio ~ p(x, pen = "ggflasso") + gene + batch}
#' See \code{\link[smurf]{glmsmurf}} for more details
#' @param model Either \code{"binomial"} or \code{"gaussian"} used to fit
#' the generalized fused lasso
#' @param genecluster which gene cluster to run the fused lasso on.
#' Usually one first identifies an interesting gene cluster pattern by
#' \code{\link{summaryAllelicRatio}}
#' @param niter number of iterations to run; recommended to run 5 times
#' if allelic ratio differences across cell types are within [0.05, 0.1]
#' @param pen.weights argument as described in \code{\link[smurf]{glmsmurf}}
#' @param lambda argument as described in \code{\link[smurf]{glmsmurf}}.
#' Default lambda is determined by \code{"cv1se.dev"}
#' (cross-validation within 1 standard error rule(SE); deviance)
#' @param k number of cross-validation folds
#' @param adj.matrix argument as described in \code{\link[smurf]{glmsmurf}}
#' @param lambda.length argument as described in \code{\link[smurf]{glmsmurf}}
#' @param se.rule.nct the number of cell types to trigger a different SE-based rule than 1 SE
#' (to prioritize larger models, less fusing,
#' good for detecting smaller, e.g. 0.05, allelic ratio differences).
#' When the number of cell types is less than or equal to this value,
#' \code{se.rule.mult} SE rule is used. When the number of cell types
#' is larger than this value, the standard 1 SE rule is used.
#' @param se.rule.mult the multiplier of the SE in determining the lambda:
#' the chosen lambda is within \code{se.rule.mult} x SE of the minimum deviance.
#' Small values will prioritize larger models, less fusing.
#' Only used when number of cell types is equal to or less than \code{se.rule.nct}
#' @param ... additional arguments passed to \code{\link[smurf]{glmsmurf}}
#'
#' @return A SummarizedExperiment with attached metadata and colData:
#' a matrix grouping factor partition
#' and the penalized parameter lambda
#' are returned in metadata \code{"partition"} and \code{"lambda"}.
#' Partition and logistic group allelic estimates are stored in
#' colData: \code{"part"} and \code{"coef"}.
#'
#' @details Usually, we used a Generalized Fused Lasso penalty for the
#' cell states in order to regularize all possible coefficient differences.
#' Another possibility would be to use the Graph-Guided Fused Lasso penalty
#' to only regularize the differences of coefficients of neighboring
#' cell states.
#'
#' When using a Graph-Guided Fused Lasso penalty, the adjacency matrix
#' corresponding to the graph needs to be provided. The elements of this
#' matrix are zero when two levels are not connected, and one when they are
#' adjacent.
#'
#' See the package vignette for more details and a complete description of a
#' use case.
#'
#' @references
#'
#' This function leverages the glmsmurf function from the smurf package.
#' For more details see the following manuscript:
#'
#' Devriendt S, Antonio K, Reynkens T, et al.
#' Sparse regression with multi-type regularized feature modeling[J].
#' Insurance: Mathematics and Economics, 2021, 96: 248-261.
#'
#' @seealso \code{\link[smurf]{glmsmurf}},
#' \code{\link[smurf]{glmsmurf.control}},
#' \code{\link[smurf]{p}}, \code{\link[stats]{glm}}
#'
#' @examples
#' library(S4Vectors)
#' library(smurf)
#' sce <- makeSimulatedData()
#' sce <- preprocess(sce)
#' sce <- geneCluster(sce, G = seq_len(4))
#' f <- ratio ~ p(x, pen = "gflasso") # formula for the GFL
#' sce_sub <- fusedLasso(sce,
#'   formula = f, model = "binomial", genecluster = 1, ncores = 1)
#' metadata(sce_sub)$partition
#' metadata(sce_sub)$lambda
#'
#' # can add covariates or `gene` to the formula
#' f2 <- ratio ~ p(x, pen = "gflasso") + gene
#' sce_sub <- fusedLasso(sce[1:5,],
#'   formula = f2, model = "binomial",
#'   genecluster = 1, ncores = 1)
#' 
#' # Suppose we have 4 cell states, if we only want neibouring cell states
#' # to be grouped together with other cell states. Note here the names of
#' # the cell states should be given as row and column names.
#' nct <- nlevels(sce$x)
#' adjmatrix <- makeOffByOneAdjMat(nct)
#' colnames(adjmatrix) <- rownames(adjmatrix) <- levels(sce$x)
#' f <- ratio ~ p(x, pen = "ggflasso") # use graph-guided fused lasso
#' sce_sub <- fusedLasso(sce,
#'   formula = f, model = "binomial", genecluster = 1,
#'   lambda = 0.5, ncores = 1,
#'   adj.matrix = list(x = adjmatrix)
#' )
#' metadata(sce_sub)$partition
#' @import smurf
#' @importFrom matrixStats rowSds
#' @importFrom stats binomial gaussian terms
#'
#' @export
fusedLasso <- function(sce, formula, model = c("binomial", "gaussian"),
                       genecluster,
                       niter = 1,
                       pen.weights, lambda = "cv1se.dev", k = 5,
                       adj.matrix, lambda.length = 25L,
                       se.rule.nct = 8,
                       se.rule.mult = 0.5,
                       ...) {
  model <- match.arg(model, c("binomial", "gaussian"))
  if (missing(genecluster)) stop("No gene cluster number")
  stopifnot(c("ratio", "counts") %in% assayNames(sce))
  stopifnot("x" %in% names(colData(sce)))
  stopifnot("cluster" %in% names(rowData(sce)))
  if (missing(formula)) {
    formula <- ratio ~ p(x, pen = "gflasso")
  }
  ## default is empty list
  if (missing(adj.matrix)) {
    adj.matrix <- list()
  }
  sce_sub <- sce[rowData(sce)$cluster == genecluster, ]
  cl_ratio <- as.vector(unlist(assays(sce_sub)[["ratio"]]))
  x_factor <- factor(rep(sce_sub$x, each = length(sce_sub)))
  cl_total <- as.vector(unlist(assays(sce_sub)[["counts"]]))
  gene <- factor(rep(seq_len(nrow(sce_sub)),times=ncol(sce_sub)))
  dat <- data.frame(
    ratio = cl_ratio,
    x = x_factor,
    cts = cl_total,
    gene = gene
  )
  index <- !is.nan(dat$ratio)
  dat <- dat[index, ]
  x <- model.matrix(~ x,dat)
  stopifnot(qr(x)$rank==ncol(x))
  # are there additional covariates besides x?
  add_covs <- grep("p\\(",
    attr(terms(formula), "term.labels"),
    invert = TRUE, value = TRUE
    )
  # adding covariates to `dat`, current this only supports factors
  if (length(add_covs) > 0) {
    for (v in setdiff(add_covs, "gene")) {
      dat[[v]] <- factor(rep(sce_sub[[v]], each=nrow(sce_sub)))[index]
      dat[[v]] <- droplevels(dat[[v]])
    }
  }
  
  if (model == "binomial") {
    fam <- binomial(link = "logit")
    msg <- "Failed determining max lambda, try other lambda, weights or gaussian model"
    weight <- dat$cts
  } else if (model == "gaussian") {
    fam <- gaussian()
    msg <- "Failed determining max of lambda, try other lambda or weights"
    weight <- NULL
  }
  nct <- nlevels(sce$x)
  ## need to use tryCatch to avoid lambda.max errors
  res <- tryCatch({
    sapply(seq_len(niter), function(t) {
      fitSmurf(
        t, formula, fam, dat, adj.matrix,
        weight, lambda, lambda.length, k,
        nct, se.rule.nct, se.rule.mult, ...)
    })
  }, error = function(e) {
    message(msg)
    return(NA)
  })
  if (length(res) == 1 && is.na(res)) {
    stop("Error occurred in attempting to run fused lasso")
  }
  if (niter == 1) {
    coef <- res[seq_len(nct), ]
    lambda <- unname(res[nrow(res), ])
    part <- match(coef, unique(coef)) %>% as.factor()
  } else {
    ## multiple partitions
    coef <- res[seq_len(nct), ]
    lambda <- res[nrow(res), ]
    part <- apply(coef, 2, function(z) match(z, unique(z)))
    colnames(part) <- paste0("part", seq_len(niter))
    colnames(coef) <- paste0("coef", seq_len(niter))
    names(lambda) <- paste0("part", seq_len(niter))
  }
  cl <- data.frame(part, x = levels(sce_sub$x), coef)
  colData(sce_sub)$part <- cl$part[match(colData(sce_sub)$x, cl$x)]
  colData(sce_sub)$coef <- cl$coef[match(colData(sce_sub)$x, cl$x)]
  metadata(sce_sub)$partition <- cl
  metadata(sce_sub)$lambda <- lambda
  sce_sub
}

fitSmurf <- function(t, formula, fam, dat, adj.matrix,
                     weight, lambda, lambda.length, k,
                     nct, se.rule.nct, se.rule.mult, ...) {
  fit <- smurf::glmsmurf(
    formula = formula, family = fam,
    data = dat, adj.matrix = adj.matrix,
    weights = weight,
    pen.weights = "glm.stand", lambda = lambda,
    control = list(lambda.length = lambda.length, k = k, ...)
  )
  co <- coef_reest(fit)
  co <- co + c(0, rep(co[1], nct - 1), rep(0, length(co) - nct))
  fit_lambda <- fit$lambda
  selection <- sub("\\..*", "", lambda)
  ## if number of cell types is 'se.rule.nct' or less:
  if (nct <= se.rule.nct & grepl("cv", selection)) {
    metric <- sub(".*\\.", "", lambda)
    ## choose lambda by the lowest deviance within 'se.rule.mult'
    ## standard error of the min
    mean.dev <- rowMeans(fit$lambda.measures[[metric]])
    min.dev <- min(mean.dev)
    sd.dev <- matrixStats::rowSds(fit$lambda.measures[[metric]])
    se.dev <- mean(sd.dev) / sqrt(k)
    idx <- which(mean.dev <= min.dev + se.rule.mult * se.dev)[1]
    ## this is faster, running the GFL for a single lambda value
    fit2 <- smurf::glmsmurf(
      formula = formula, family = fam,
      data = dat, adj.matrix = adj.matrix,
      weights = weight, pen.weights = "glm.stand",
      lambda = fit$lambda.vector[idx]
    )
    ## rearrange coefficients so not comparing to reference cell type
    co <- coef_reest(fit2)
    co <- co + c(0, rep(co[1], nct - 1), rep(0, length(co) - nct))
    fit_lambda <- fit2$lambda
  }
  ## stick the fitted means with the lambda on the end of the vector
  c(co, fit_lambda)
}


#' Generating adjancy matrix for neighboring cell states.
#'
#' To use the Graph-Guided Fused Lasso penalty to only regularize the differences
#' of coefficients of neighboring areas, suitable for time/spatial analysis.
#' The adjacency matrix corresponding to the graph needs to be provided.
#' The elements of this matrix are zero when two levels are not connected, and one when they are adjacent.
#'
#' @param nct the number of cell types/states
#' @details If manually input the adjacency matrix, this matrix has to be symmetric and the names of
#' the cell states should be given as row and column names.
#'
#' @examples
#' sce <- makeSimulatedData()
#' nct <- nlevels(sce$x)
#' adjmatrix <- makeOffByOneAdjMat(nct)
#' colnames(adjmatrix) <- rownames(adjmatrix) <- levels(sce$x)
#'
#' @export
makeOffByOneAdjMat <- function(nct) {
  b <- matrix(0, nct, nct)
  a <- diag(nct - 1)
  b[lower.tri(b, diag = FALSE)] <- a[lower.tri(a, diag = TRUE)]
  b + t(b)
}
