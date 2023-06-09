library(org.Sc.sgd.db)
library(gplots)
library(ggplot2)

thedir <- getwd() # Location of this script (assumes that working directory is the folder containing this script)

getDeleteomeExpData <- function() {
  # Note that column name "atg4_del_1_vs_wt" was changed to "atg4_del_vs_wt"
  message("Loading deleteome expression data from ", thedir)
  load(paste0(thedir,"/deleteome_exp_data.RData"))
  return(alldata)
}


getPathToDeleteomeFolder <- function(){
  return(thedir)
}

# collect systematicNames and M values (log2 fold-changes) for a given deletion
# any column in the deleteome that doesn't have "del" in the name is ignored (a data frame with 0 rows is returned)
getProfileForDeletion <- function(delData, deletionname, Mthresh, pthresh, consoleMessages=T){
  
  if(consoleMessages){
    message(paste0("Getting log2 fold-change values for ", deletionname, " from deleteome"))
  }
  
  McolSuffix <- "_wt"
  if("deleteomeResponsiveOnly" %in% class(delData)){
    McolSuffix <- "_wt_1"
  }
  
  Mcolname <- paste0(deletionname,"_del_vs",McolSuffix)
  pcolname <- paste0(deletionname,"_del_vs_wt_2")
  
  if(Mcolname %in% names(delData) & pcolname %in% names(delData)){
    selected <- delData[abs(as.numeric(delData[,Mcolname]))>=Mthresh & as.numeric(delData[,pcolname])<=pthresh,c("systematicName","geneSymbol",Mcolname,pcolname)]
    selected <- selected[selected$geneSymbol!=toupper(deletionname),]
    selected[,3] <- as.numeric(selected[,3])
    selected[,4] <- as.numeric(selected[,4])
  }
  else{
    if(consoleMessages){
      message(c("Could not find expression and/or p-values for ", Mcolname, " and ", pcolname))
    }
    temp <- data.frame(matrix(nrow=0,ncol=4))
    names(temp) <- c("systematicName","geneSymbol",Mcolname,pcolname)
    return(temp)
  }
  return(selected)
  
}

# Get names of all mutant strains in Deleteome data
getAllStrainNames <- function(deleteomeData){
  
  # This excludes strains in deleteome that start with "WT_" ("WT-MATA"    "WT-BY4743"  "WT-YPD"). 
  # From https://deleteome.holstegelab.nl/: "These In addition, three control experiments, matA versus matAlpha, 
  # YPD versus SC and BY4343 versus BY4342 (diploid versus haploid) have been added for easier comparison to external datasets."
  colheads <- gsub("_vs.*","",names(deleteomeData))
  colheads <- gsub("_del","",colheads)
  colheads <- colheads[ ! colheads %in% c("systematicName","geneSymbol")] # exclude systematicName and geneSymbol columns
  
  return(sort(unique(colheads)))
}

# Get genomic locations for genes
getGenePositions <- function(includeMito=F) # includeMito indicates whether to include mitochondrial genes
  {
  
  gppath <- paste0(thedir, "/data/genePositions.csv")
  centpath <- paste0(thedir, "/data/YeastMine_CentromerePositions.tsv")
  cnlpath <- paste0(thedir, "/data/chrNameLength.txt")
  
  # Create table that associates gene ID with chromosome, as well as start and end positions on chromosome
  genePositions <- read.table(gppath, sep=',',quote="",stringsAsFactors=F,header=T)
  centPositions <- read.table(centpath, sep="\t", quote="", stringsAsFactors = F, header=T)
  
  # Remove mitochondrial genes, if requested
  if( ! includeMito){
    genePositions <- genePositions[! grepl("Mito",genePositions$Chr),]
  }
  
  # Column name for distances from telomere 
  dftname = "dist_from_telo"
  
  # Columne name for distances from centromere
  dfcname <- "dist_from_cent"
  
  genePositions[,dftname] <- NA
  genePositions[,dfcname] <- NA
  
  # Create table of chromosome names and lengths
  chrNameLengths <- read.table(cnlpath, header=FALSE, sep="\t")
  
  # Create table that associates gene with distance from telomere
  message("Computing gene distances from telomere and centromere")
  
  for(geneid in genePositions[,1]){
    
    rowNum = which(genePositions[,1] == geneid)
    
    # get chromosome containing the gene. Convert from data frame element to character array.
    chrName = genePositions[rowNum, "Chr"]
    
    # get gene start position
    geneStartPos = genePositions[rowNum, "Start"]
    geneEndPos = genePositions[rowNum, "End"]
    
    # look up chromosome length
    chrLength = chrNameLengths[which(chrNameLengths[,1] == chrName),2]
    
    distFromCent <- NA
    
    if(chrName!="Mito"){
    # look up position of centromere on chromosome
      chrCentStart <- as.integer(centPositions[centPositions$Description==paste0("Chromosome ",chrName, " centromere"),"Start"])
      chrCentEnd <- as.integer(centPositions[centPositions$Description==paste0("Chromosome ",chrName, " centromere"),"End"])
      
      # compute distance from centromere
      # NOTE: THIS COMPUTES DISTANCE USING EITHER START OR END OF GENE, WHICHEVER IS CLOSEST TO CENTROMERE
      if(geneEndPos < chrCentStart){
        distFromCent <- chrCentStart-geneEndPos
      }
      else if(geneStartPos > chrCentEnd){
        distFromCent <- geneStartPos-chrCentEnd
      }
      else{
        message("ERROR: ",geneid," is neither ahead of or behind centromere") # would only be thrown if a gene that overlaps the centromere
        return(NULL)
      }
    }
    
    # compute distance from telomere
    distFromChrStart = (geneStartPos - 1)
    distFromChrEnd = (chrLength - geneStartPos)
    distFromTelo = min(distFromChrStart, distFromChrEnd)
    genePositions[rowNum, dftname] <- distFromTelo
    
    genePositions[rowNum, dfcname] <- distFromCent
  }
  return(genePositions) # Used to be na.omit(genePositions) but if include mitogenes, then dist from cent is included as NA
}

# Test enrichment for differentially-expressed genes in the subtelomeric region
subtelomericEnrichment <- function(genePositions=NULL, # table of genes and their genomic positions (obtainable using getGenePositions())
                                   systematicNamesBG,  # background list of genes for enrichment test
                                   systematicNames,    # list of genes to test for enrichment
                                   includeMito=F,      # whether to include mitochondrial genes in analysis
                                   rangeInKB=25        # telomere length in kilobases
                                   ){      
  
  return(genomicRegionEnrichment(genePositions=genePositions, systematicNamesBG=systematicNamesBG, systematicNames=systematicNames, includeMito=includeMito, relativeTo="telomere", rangeInKB=rangeInKB))
}

# Test enrichment for differentially-expressed genes in the centromeric region
centromericEnrichment <- function(genePositions=NULL,  # table of genes and their genomic positions (obtainable using getGenePositions())
                                  systematicNamesBG,   # background list of genes for enrichment test
                                  systematicNames,     # list of genes to test for enrichment
                                  includeMito=F,       # whether to include mitochondrial genes in analysis
                                  rangeInKB=25         # size of genomic region before and after centromere considered to be centromeric
                                  ){
  
  return(genomicRegionEnrichment(genePositions=genePositions, 
                                 systematicNamesBG=systematicNamesBG, 
                                 systematicNames=systematicNames, 
                                 includeMito=includeMito, 
                                 relativeTo="centromere", 
                                 rangeInKB=rangeInKB))
}


genomicRegionEnrichment <- function(genePositions=NULL, 
                                    systematicNamesBG, 
                                    systematicNames, 
                                    includeMito=F, 
                                    relativeTo="telomere",  # accepted values for relativeTo are "telomere" or "centromere"
                                    rangeInKB=25){  
  
  if(is.null(genePositions)){
    genePositions <- getGenePositions(includeMito=includeMito)
  }
  
  if(length(systematicNames)==0){
    message("ERROR: Genomic region enrichment test not performed because input gene list was empty")
    return()
  }
  
  # limit the background set of genes to only those in systematicNamesBG
  genePositions <- genePositions[which(genePositions$Geneid %in% systematicNamesBG),]
  
  dfname = "dist_from_telo"
  dfkbname = "dist_from_telo_in_kb"
  
  if(relativeTo=="centromere"){
    dfname = "dist_from_cent"
    dfkbname = "dist_from_cent_in_kb"
  }
  
  
  res <- data.frame(systematicName=as.character(systematicNames), 
                    x=as.numeric(NA),stringsAsFactors=F)
  names(res)[2] <- dfkbname
  
  # Record distance from region for each gene in results
  for( geneid in systematicNames ){
    
    rowWithDist = which(genePositions[,1]==geneid)

    if(length(rowWithDist) == 1 ){
      df = genePositions[rowWithDist,dfname]
      res[res$systematicName==geneid, dfkbname] <- df/1000	 # convert from bases to kilobases
    }
    else{
      message(paste0("WARNING: number of matching rows in gene positions table for gene ", geneid, " did not equal 1"))
    }
  }
  
  message("Done collecting gene distances from region")
  res <- na.omit(res)

  # compute hypergeometrics to see if list of signficantly upregulated
  # genes are enriched for genes near the region of interest
  samplesuccesses <- length(which(res[,dfkbname]<=rangeInKB))
  samplesize <- length(res[,dfkbname])
  
  popsuccesses <- length(which(genePositions[,dfname]<=rangeInKB*1000))
  popsize <- length(genePositions[,dfname])
  
  hyperp = phyper(samplesuccesses-1, popsuccesses, (popsize-popsuccesses), samplesize, lower.tail=F) # the minus 1 is because probabilities are P[X>x] by default but we want P[X>=x]
  
  message(c("\nPopulation size: ", popsize, " Population successes: ", popsuccesses, " Sample size: ", samplesize, " Sample successes: ", samplesuccesses))

  return(hyperp)
}

# Perform GO enrichment on a list of genes
# Gene names such as "nup170" should be used as input
# By default, uses the list of mutants in the deleteome as the background for the enrichment tests
# Performs enrichment test over GO:BP, GO:MF and GO:CC sub-ontologies
doGOenrichmentOnDeleteomeMatches <- function(deleteomeData, genes=c(), 
                                             useDeleteomeBackground=T, 
                                             pthresh=0.05){ # uses gene names not systematic names
  
  suppressMessages(suppressWarnings(require(clusterProfiler)))
  require(org.Sc.sgd.db)
  
  genes <- toupper(genes)
  
  message("Performing GO enrichment tests")
  
  if(useDeleteomeBackground){
    bg <- toupper(getAllStrainNames(deleteomeData))
    xGOUni <- enrichGO(genes, pvalueCutoff = pthresh, minGSSize = 2, OrgDb=org.Sc.sgd.db::org.Sc.sgd.db, keyType = "GENENAME", pAdjustMethod = "BH", universe = bg, ont="ALL")
  }
  else{
    xGOUni <- enrichGO(genes, pvalueCutoff = pthresh, minGSSize = 2, OrgDb=org.Sc.sgd.db::org.Sc.sgd.db, keyType = "GENENAME", pAdjustMethod = "BH", ont="ALL")
  }
  detach("package:clusterProfiler", unload=TRUE)
  return(xGOUni[,])
}


# Make a heatmap showing expression profiles of matched mutants
makeHeatmapDeleteomeMatches <- function(mutantname=NA,         # Name of deletion strain (used for plot titles and file names)
                                        mutantProfile=NA,      # Gene expression signature for deletion strain (can be obtained using getProfileForDeletion())
                                        selectedConditions=NA, # List of additional Deleteome strains to include in heatmap
                                        fileprefix=NA,         # String that can be added to beginning of heatmap file name. Appears after mutant name.
                                        titledesc="",          # Rationale for inclusion of additional strains in heatmap. Used in title of heatmap.
                                        MthreshForTitle=NA,    # Log2 fold-change threshold used to get the mutant strain's signature. Only used in heatmap title.
                                        pthreshForTitle=NA,    # P-value threhshold used to get the mutant strain's signature. Only used in heatmap title.
                                        subteloGenesOnly=F,    # Whether to only include subtelomeric genes in the rows of the heatmap
                                        colFontSize=1,         # Font size for column labels
                                        showRowLabels=F,       # Whether to show row labels
                                        rowFontSize=0.275,     # Font size for row labels
                                        imagewidth=3000,       # If writing to file, the Width of the saved image in pixels
                                        imageheight=2400,      # If writing to file, the Width of the saved image in pixels
                                        printToFile=T          # Whether to write heatmap to a file or show in new window
                                        ){
  # make heatmap comparing all significantly matched mutants to mutant of interest
  
  # SOMETIMES THE COND IS IN THE MUTANTPROFILE$GENESYMBOL, BUT NOT IN THE CONDPROFILEALL
  # SO REMOVE ROWS IN MUTANTPROFILE THAT MATCH A COND
  genesThatCanBeCompared <- mutantProfile[ ! mutantProfile$geneSymbol %in% toupper(selectedConditions),]
  
  subtelosuffix <- ""
  rowtitleprefix <- "Genes"
  
  if(subteloGenesOnly){
    subtelosuffix <- "\n Subtelomeric genes only"
    gps <- getGenePositions()
    subgps <- gps[gps$dist_from_telo<25000,"Geneid"]
    genesThatCanBeCompared <- genesThatCanBeCompared[genesThatCanBeCompared$systematicName %in% subgps,]
    rowtitleprefix <- "Subtelomeric genes"
  }
  
  sigcorrheatmap <- data.frame(Gene=as.character(genesThatCanBeCompared$systematicName), stringsAsFactors=F)
  sigcorrheatmap[,mutantname] <- as.numeric(mutantProfile[mutantProfile$systematicName %in% genesThatCanBeCompared$systematicName,3])
  
  # Collect transcriptional profiles for Deleteome strains that will be included in the heatmap
  for(cond in selectedConditions){
    condprofileALL <- getProfileForDeletion(alldata, cond, 0, 1, consoleMessages = F)
    condhmdatadf <- condprofileALL[condprofileALL$systematicName %in% genesThatCanBeCompared$systematicName, c(2,3)]
    condhmdata <- condhmdatadf[,2]
    names(condhmdata) <- condhmdatadf[,1]
    sigcorrheatmap[,cond] <- as.numeric(condhmdata)
  }
  
  mybigmat <- data.matrix(sigcorrheatmap[,-1])
  rownames(mybigmat) <- sigcorrheatmap$Gene
  
  mybreaks <- seq(-1.5, 1.5, length.out=101)
  
  if(printToFile){
    hmfile <- paste0(thedir, "/output/Heatmaps/",mutantname,"_",fileprefix,"Heatmap_l2FC_",MthreshForTitle,"_p",
                      pthreshForTitle,".jpg")
    jpeg(file = hmfile, 
            width=imagewidth, height = imageheight, res=300, units="px")
  }
  else{
    dev.new(width=10,height=8,noRStudioGD = TRUE)
  }
  
  par(cex.main=0.75) ## this will affect also legend title font size
  
  rowlabels <- rownames(mybigmat)
  rightmar <- 5
  
  if( ! showRowLabels){
    rowlabels = rep("",dim(mybigmat)[1])
    rightmar <- 2
  }
  
  # Make the heatmap object
  clust <- heatmap.2(mybigmat,Colv=T, trace="none", symbreaks=T, 
                     xlab = "Mutant strain", ylab = paste0(rowtitleprefix, " in ", mutantname, " deletion signature"),
                     labRow = rowlabels,
                     symm=F,symkey=F, 
                     scale="none", 
                     breaks=mybreaks, 
                     margins=c(6,rightmar), # Makes sure the y-axis label is more flush with plot
                     cexCol=colFontSize, 
                     cexRow=rowFontSize,
                     col = colorRampPalette(c("blue","white","red"))(100), 
                     key.title= "",
                     keysize = 1,
                     key.xlab = "Log2 fold-change vs. WT",
                     main=paste0("Expression for ", mutantname, 
                                 " deletion and other deleteome strains\nbased on ", titledesc, "\nLog2 fold-change cutoff: ",
                                            MthreshForTitle, ", P-value cutoff: ", pthreshForTitle, subtelosuffix))
  
  if(printToFile){ 
    dev.off()
    message("Printed heatmap to ", hmfile)
  }
  
  return(mybigmat)
}


# Mountain lake plots
makeGenomicPositionHistogram <- function(alldata=NULL,           # Full Deleteome data set object (can be obtained using getDeleteomeExpData())
                                         mutant=NULL,            # Name of Deleteome mutant strain to analyze
                                         genePositions=NULL,     # Table of genes and genomic positions (can be obtained using getGenePositions())
                                         relativeTo="telomere",  # can be "telomere" or "centromere"
                                         rangeInKB=25,           # Window (in kilobases) for defining a gene as either in the telomeric or centromeric region
                                         Mthresh=0,              # Log2 fold-change threshold for defining differentially-expressed genes
                                         pthresh=0.05,           # P-value threshold for defining differentially-expressed genes
                                         xmax=500,               # X-axis maximum
                                         ymax=50,                # Y-axis maximum
                                         upcolor="red",          # Color to use for upregulated genes
                                         downcolor="blue",       # Color to use for downregulated genes
                                         showupdownlabels=T,     # Whether to inclue "upregulated" and "downregulated" labels in plot
                                         file=NA                 # Optional file location to save plot. If NA (default), plot is shown in new window.
                                         ){ 
  
  if(is.null(mutant)){
    message("Cannot produce genomic position histogram: mutant ID is NA")
  }
  
  message("Making genomic position histogram for mutant ", mutant)
  
  if(is.null(alldata)){
    message("Loading full deleteome data set")
    alldata <- getCachedDeleteomeAll()
  }
  
  if(is.null(genePositions)){
    message("Loading gene positions across deleteome. Excluding mitochondrial genes.")
    genePositions <- getGenePositions(includeMito = F)
  }
  
  if(relativeTo=="telomere"){
    relativeToCol <- "dist_from_telo"
  }
  else if(relativeTo=="centromere"){
    relativeToCol <- "dist_from_cent"
  }
  
  # Use the following to show VdVFig3 plots of selected mutants
  allDF <- genePositions[,relativeToCol]/1000 # get all distance from telomere numbers; filter out mitochondrial genes? If so: genePositions$Chr != 'Mito'

  mutantProfile <- getProfileForDeletion(alldata, mutant, Mthresh, pthresh, consoleMessages = F)
  
  profileUP <- mutantProfile[mutantProfile[,3] > Mthresh, ]
  profileDOWN <- mutantProfile[mutantProfile[,3] <= -Mthresh, ]
  profileAll <- getProfileForDeletion(alldata, mutant, 0, 999, consoleMessages = F)
  
  upDF <- genePositions[genePositions$Geneid %in% profileUP$systematicName,relativeToCol]
  downDF <- genePositions[genePositions$Geneid %in% profileDOWN$systematicName,relativeToCol]
  
  upDF <- na.omit(upDF/1000)
  downDF <- na.omit(downDF/1000)
  
  message("Number of significantly upregulated genes: ", length(upDF))
  message("Number of significantly downregulated genes: ", length(downDF))
  
  mybreaks = seq(from=0, to=max(na.omit(genePositions[,relativeToCol]))/1000, by=5)
  
  if(relativeTo=="telomere"){
    mybreaks <- c(mybreaks,770) # max dist from telo in genePositions is 765.197 kb. Need one more breakpoint for histogram to include it.
  }
  else{
    mybreaks <- c(mybreaks, 1085) # max dist from telo in genePositions is 1081.042 kb. Need one more breakpoint for histogram to include it.
  }
  
  regionUPhyperp <- genomicRegionEnrichment(genePositions, 
                                            systematicNamesBG=profileAll[profileAll$systematicName %in% genePositions$Geneid, "systematicName"], 
                                            systematicNames=profileUP[profileUP$systematicName %in% genePositions$Geneid, "systematicName"], 
                                            relativeTo = relativeTo, rangeInKB = rangeInKB)
  message("Hypergeometric test P-value for upregulated subtelomeric genes: ", regionUPhyperp)
  
  regionDOWNhyperp <- genomicRegionEnrichment(genePositions, systematicNamesBG=profileAll[profileAll$systematicName %in% genePositions$Geneid, "systematicName"], 
                                              systematicNames=profileDOWN[profileDOWN$systematicName %in% genePositions$Geneid, "systematicName"],
                                              relativeTo = relativeTo, rangeInKB = rangeInKB)
  message("Hypergeometric test P-value for downregulated subtelomeric genes: ", regionDOWNhyperp)
  
  # ggplot2 style
  upDFgg <- as.data.frame(upDF)
  names(upDFgg) <- "dist"
  downDFgg <- as.data.frame(downDF)
  names(downDFgg) <- "dist"
  updownDF <- rbind()
  allDFgg <- as.data.frame(allDF)
  names(allDFgg) <- "dist"
  
  p <- ggplot() +
    geom_histogram(data = allDFgg, aes(x = dist, y = after_stat(count)/3), fill="gray", binwidth = 5, boundary=-5) + 
    geom_histogram(data = allDFgg, aes(x = dist, y = -after_stat(count)/3), fill="gray", binwidth = 5, boundary=-5) + 
    geom_histogram(data = upDFgg, aes(x = dist, y = after_stat(count)), fill=upcolor, binwidth = 5, boundary=-5) +
    geom_histogram(data = downDFgg, aes(x = dist, y = -after_stat(count)), fill= downcolor, binwidth = 5, boundary=-5) +
    scale_x_continuous(breaks=seq(0,xmax,by=25)) +
    theme(plot.title = element_text(size=25, face="bold"), axis.text=element_text(size=11),
           axis.title=element_text(size = 18,face="plain"), axis.text.x = element_text(angle = 45, hjust=1)) +
    xlab(paste0("Distance from ",relativeTo," (kb)")) + 
    ylab(paste0("Number of ORFs")) + 
    ggtitle(bquote(italic(.(mutant)*Delta)))
  
  # Show the "upregulated" and "downregulated" labels if desired
  if(showupdownlabels){
    p <- p + annotate("text", x=(xmax-(xmax/4)), y=(ymax-(ymax/4)), label= "upregulated", color=upcolor, size = 6) +
      annotate("text", x=(xmax-(xmax/4)), y=(-ymax+(ymax/4)), label= "downregulated", color=downcolor, size = 6)
  }
  
  if(is.na(file)){
    dev.new(width=9,height=5.5, noRStudioGD = T)
  }
  else{
    png(filename = file, width=9, height=5.5, res=300, units="in")
  }  
  
  print(p)
  
  if( ! is.na(file)){
    dev.off()
  }
}

# Find mutants with similar expression profiles using hypergeometric enrichment tests
getDeleteomeMatchesByReciprocalCorrelation = function(mutant=NA,           # Name of Deleteome strain to analyze
                                                      minAbsLog2FC=0,      # Log2 fold-change cutoff used to classify genes as differentially expressed 
                                                                           #   (absolute value of log2 fold-change must be higher than minAbsLog2FC)
                                                      pCutoff=0.05,        # P-value cutoff used to identify differentially-expressed genes
                                                      quantileCutoff=0.05, # Quantile cutoff for selecting the Deleteome matches with highest confidence
                                                      deleteomeData=NA,    # Full Deleteome expression data set (can be obtained using getDeleteomeExpData())
                                                      showMessages = F     # Whether to output progress messages
                                                      ){
  
  message("Getting deleteome matches by reciprocal correlation...")
  alldata <- deleteomeData
  
  if( ! is.data.frame(alldata)){
    alldata <- getCachedDeleteomeAll()
  }
  
  conds <- getAllStrainNames(alldata)
  
  if( ! mutant %in% conds){
    stop(paste0(mutant, " is not in deleteome"))
  }
  
  mutantProfile <- getProfileForDeletion(alldata, mutant, minAbsLog2FC, pCutoff, consoleMessages = showMessages)
  
  if(dim(mutantProfile)[1]==0){
    message(c(mutant," had no significantly changed genes, based on M-value and p-value thresholds"))
    return(c())
  }
  
  
  # get the direct correlations between the mutant and all other deleteome mutants
  allCorrResults <- data.frame(Deletion=as.character(),
                               CorrCoefficient=as.numeric(),
                               Pvalue=as.numeric(), 
                               stringsAsFactors=F)
  
  h = 1
  
  conditions <- getAllStrainNames(alldata)
  
  for(cond in conditions){
    
    if(cond %in% c("wt_matA","wt_by4743","wt_ypd")){
      next() # Skip the WT control experiments in the deleteome
    }
    
    allconddata <- getProfileForDeletion(alldata, cond, 0, 1, consoleMessages = showMessages)
    intrsct <- intersect(mutantProfile$systematicName, allconddata$systematicName) # need to do this b/c condition profile won't include the KO'd gene, which might be in the mutant's profile
    
    if(length(intrsct) > 2){
      
      correl <- cor.test(allconddata[allconddata$systematicName %in% intrsct,3],mutantProfile[mutantProfile$systematicName %in% intrsct,3])
      Rval <- as.vector(correl["estimate"][[1]])
      pval <- as.vector(correl["p.value"][[1]])
    }
    else{
      Rval <- NA
      pval <- NA
      message("Not enough overlap in signatures for ", cond)
    }
    allCorrResults[h,] <- c(cond, Rval, pval)
    h = h+1
  }
  
  allCorrResults$Pvalue.FDR <- as.numeric(p.adjust(allCorrResults$Pvalue, method = "BH"))
  
  allCorrResultsNoNA <- allCorrResults[ ! is.na(allCorrResults$CorrCoefficient) & ! is.na(allCorrResults$Pvalue), ]
  
  allCorrResultsNoNA$CorrCoefficient <- as.numeric(allCorrResultsNoNA$CorrCoefficient)
  allCorrResultsNoNA$Pvalue <- as.numeric(allCorrResultsNoNA$Pvalue)
  allCorrResultsNoNA$Pvalue.FDR <- as.numeric(allCorrResultsNoNA$Pvalue.FDR)
  
  
  allSigCorrResults <- allCorrResultsNoNA[allCorrResultsNoNA$CorrCoefficient > 0,] # limit to positive correlations
  
  pvalcutoff <- quantile(allSigCorrResults$Pvalue.FDR, quantileCutoff) # get mutants with pvals that were significantly better than overall
  
  
  allSigCorrResults <- allSigCorrResults[allSigCorrResults$Pvalue.FDR < pvalcutoff,]
  allSigCorrResults <- allSigCorrResults[order(allSigCorrResults$CorrCoefficient,decreasing=T),]
  
  
  # for each signifcantly correlated mutant, see if reciprocal correlation is also significant
  allRecipCorrResults = data.frame(matrix(ncol=3, nrow=length(allSigCorrResults$Deletion)))
  names(allRecipCorrResults) = c("Deletion", "CorrCoefficient","Pvalue")
  
  m = 1
  
  mutantProfileANY <- getProfileForDeletion(alldata, mutant, 0, 1, consoleMessages = showMessages)
  for(cond in allSigCorrResults$Deletion){
    
    condprofile <- getProfileForDeletion(alldata, cond, minAbsLog2FC, pCutoff, consoleMessages = showMessages)
    
    intrsct <- intersect(mutantProfileANY$systematicName,condprofile$systematicName) # need to do this b/c condition profile won't include the KO'd gene, which might be in the mutant's profile
    
    if(length(intrsct) > 2){
      correl <- cor.test(condprofile[condprofile$systematicName %in% intrsct,3],mutantProfileANY[mutantProfileANY$systematicName %in% intrsct,3])
      Rval <- as.vector(correl["estimate"][[1]])
      pval <- as.vector(correl["p.value"][[1]])
    }
    else{
      Rval <- NA
      pval <- NA
    }
    allRecipCorrResults[m,] <- c(cond,Rval,pval)
    m = m + 1
  }
  
  
  allRecipCorrResults$Pvalue.FDR <- p.adjust(allRecipCorrResults$Pvalue, method="BH")
  allRecipCorrResultsNoNA <- na.omit(allRecipCorrResults)
  
  # find overlap between direct and reciprocal correlations
  allSigRecipCorrResults <- allRecipCorrResultsNoNA[as.numeric(allRecipCorrResultsNoNA$Pvalue.FDR) <= pCutoff,]
  
  sigDirectRecipCorrNames <- intersect(allSigRecipCorrResults$Deletion,allSigCorrResults$Deletion) # get all KO's that had significant direct and reciprocal correlations
  sigDirectRecipCorrResults <- allSigCorrResults[allSigCorrResults$Deletion %in% sigDirectRecipCorrNames,]
  sigDirectRecipCorrResults <- sigDirectRecipCorrResults[order(sigDirectRecipCorrResults$CorrCoefficient,decreasing=T),] # sort by direct correlation Rval
  
  selectedConditions <- sigDirectRecipCorrResults[sigDirectRecipCorrResults$Deletion != mutant,"Deletion"]
  
  outputfilename <- paste0(thedir, "/output/mutant_similarity/",mutant,"_sigCorr_L2FC_",minAbsLog2FC,"_Pcutoff_",pCutoff,".tsv")
  write.table(sigDirectRecipCorrResults[sigDirectRecipCorrResults$Deletion != mutant, c("Deletion","CorrCoefficient","Pvalue","Pvalue.FDR")], 
            outputfilename, row.names = F, col.names = T, sep="\t", quote=F)
  message("Results written to ", outputfilename)
  
  if(length(selectedConditions)==0){
    message("Could not find any deletion mutants with signatures that significantly overlapped with ", mutant, " deletion")
  }
  
  return(selectedConditions) # Returns list of Deleteome strains matching the input strain
}




# Method to find similar deleteome mutants using hypergeometric-based approach
getDeleteomeMatchesByEnrichment <- function(mutant=NA,           # Name of Deleteome strain to analyze
                                            minAbsLog2FC=0,      # Log2 fold-change cutoff used to classify genes as differentially expressed 
                                                                 #   (absolute value of log2 fold-change must be higher than minAbsLog2FC)
                                            pCutoff=0.05,        # P-value cutoff used to identify differentially-expressed genes
                                            quantileCutoff=0.05, # Quantile cutoff for selecting the Deleteome matches with highest confidence
                                            deleteomeData=NA,    # Full Deleteome expression data set (can be obtained using getDeleteomeExpData())
                                            showMessages = F     # Whether to output progress messages
                                            ){
  
  message("Getting deleteome matches based on enrichment tests...")
  alldata <- deleteomeData
  
  if( ! is.data.frame(alldata)){
    alldata <- getCachedDeleteomeAll()
  }
  
  hypergs <- data.frame(Condition=as.character(),HyperGpval=as.numeric(), HyperGpvalFDR=as.numeric(),  
                        sampleSize=as.numeric(), sampleSuccesses=as.numeric(), popSize=as.numeric(), 
                        popSuccesses=as.numeric(), stringsAsFactors = F)
  
  conds <- getAllStrainNames(alldata)
  
  if( ! mutant %in% conds){
    stop(paste0(mutant, " is not in deleteome"))
  }
  
  nconds <- length(conds)
  
  ndeleteomegenes <- length(getProfileForDeletion(alldata, mutant, 0, 1, consoleMessages = showMessages)$systematicName)
  
  mutantprofile <- getProfileForDeletion(alldata, mutant, minAbsLog2FC, pCutoff, consoleMessages = showMessages)
  mutantprofileALL <- getProfileForDeletion(alldata, mutant, 0, 1.1, consoleMessages = showMessages)
  
  if(dim(mutantprofile)[1]==0){
    message(c(mutant," had no significantly changed genes, based on M-value and p-value thresholds"))
    return(c())
  }
  
  # compute hypergeometric test to find mutants whose signatures are enriched for the mutant of interest's signature
  for(cond in conds){
    
    if(cond==mutant){ next }
    
    profile <- getProfileForDeletion(alldata,cond,minAbsLog2FC,pCutoff, consoleMessages = showMessages)
    profileint <- computeDirectionalMatches(profile,mutantprofile)
    
    samplesuccesses <- length(profileint[profileint$samedir>0,"systematicName"])
    samplesize <- length(profile$systematicName)
    popsuccesses <- length(mutantprofile$systematicName)
    popsize <- ndeleteomegenes
    
    hyperp <- phyper(samplesuccesses-1, popsuccesses, (popsize-popsuccesses), samplesize, lower.tail=F) # the minus 1 is because probabilities are P[X>x] by default but we want P[X>=x]
    hyperpFDR <- 1 # entered later
    
    if( ! is.na(hyperp)){
      hypergs <- rbind(hypergs,data.frame(Condition=cond,HyperGpval=hyperp, HyperGpvalFDR=hyperpFDR, 
                                          sampleSize=samplesize, sampleSuccesses=samplesuccesses, 
                                          popSize=popsize, popSuccesses=popsuccesses, stringsAsFactors = F))
    }
  }
  
  hypergs$HyperGpvalFDR <- p.adjust(hypergs$HyperGpval, method = "BH")
  
  fivepctcutoff <- quantile(hypergs$HyperGpvalFDR, quantileCutoff) # make sure that we are only using the top 5% of p-values
  
  sighypergs <- hypergs[hypergs$HyperGpvalFDR<=pCutoff & hypergs$HyperGpvalFDR<=fivepctcutoff,] # 5% cutoff and must meet significance criteria
  
  orderedconds <- sighypergs[order(sighypergs$HyperGpvalFDR,decreasing=F),"Condition"] 
  
  if(length(orderedconds)==0){
    message("Could not find any deletion mutants with signatures that significantly overlapped with ", mutant, " deletion")
    return(c())
  }
  
  selectedConditions <- orderedconds
  sigresults <- sighypergs[order(sighypergs$HyperGpvalFDR,decreasing=F),1:3]
  sigresultsfile <- paste0(thedir, "/output/mutant_similarity/", mutant, "_sigHyperG_L2FC_",minAbsLog2FC,"_Pcutoff_",pCutoff,".tsv")
  write.table(sigresults, file = sigresultsfile,
              sep="\t", quote=F, row.names = F, col.names = T)
  message("Results written to ", sigresultsfile)
  
  return(selectedConditions)
}

# Used in hypergeometric analysis
computeDirectionalMatches <- function(profile1=NA, profile2=NA){
  
  profile1 <- profile1[order(profile1$systematicName),]
  profile2 <- profile2[order(profile2$systematicName),]
  
  intsct <- intersect(profile1$systematicName,profile2$systematicName)
  
  profile1int <- profile1[profile1$systematicName %in% intsct,]
  profile2int <- profile2[profile2$systematicName %in% intsct,]
  
  profile1int$mvalsToMatch <- profile2int[,3]
  profile1int$samedir <- profile1int$mvalsToMatch*profile1int[,3]
  
  return(profile1int)
}
