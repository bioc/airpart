#' Extract results from an airpart analysis
#'
#' results extracts a result table from an airpart analysis giving posterior allelic ratio estimates,
#' s values, false sign rate(fsr), upper confidence interval and lower confidence interval.
#'
#' @param sce SingleCellExperiment
#' @param estimates the estimates want to be extracted. Default is allelic ratio estimates,
#' can be \code{"svalue"}, \code{"fsr"}, \code{"lower"}(credible interval) and \code{"upper"}(credible interval)
#'
#' @return a DataFrame of estimates
#'
#' @examples
#'
#' sce <- makeSimulatedData()
#' sce <- preprocess(sce)
#' sce <- geneCluster(sce, G = 1:4)
#' sce_sub <- wilcoxExt(sce, genecluster = 1)
#' sce_sub <- allelicRatio(sce_sub)
#' ar <- extractResult(sce_sub)
#' ar
#' @export
extractResult <- function(sce, estimates = c("ar", "svalue", "fsr", "lower", "upper")) {
  estimates <- match.arg(estimates, c("ar", "svalue", "fsr", "lower", "upper"))
  estimates <- paste0(estimates,"_")
  group <- unique(data.frame(x = sce$x, part = sce$part))
  res <- rowData(sce)[, c(grep(estimates, colnames(rowData(sce)), value = TRUE))] %>%
    `colnames<-`(group$x %>% as.character())
  order <- match(levels(sce$x),colnames(res))
  res <- res[,order]
  if(estimates %in% c("svalue_","fsr_")){
    if(nrow(sce)==1){
      res <- sapply(res, as.numeric) %>% as.matrix() %>% t() %>% `rownames<-`(rownames(sce))
    }else{
      res <- DataFrame(sapply(res, as.numeric) %>% `rownames<-`(rownames(sce)))
    }
  }
  res
}
