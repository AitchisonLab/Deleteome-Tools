scriptloc <- dirname(rstudioapi::getActiveDocumentContext()$path) # Get script location
setwd(scriptloc)

# load deleteome_tools.R script
source(paste0(scriptloc, "/deleteome_tools.R")) # Assumes that deleteome_tools.R is in same directory as this file

alldata <- getDeleteomeExpData() # Load all the deleteome expression data
# getAllStrainNames(alldata) # Use this function to output a list of all available mutant strains in the Deleteome

mutantname <- "nup170" # The tool will find mutant strains transcriptionally similar to the strain specified here

Mthresh <- 0.0 # log2 fold-change cutoff for identifying differentially-expressed genes in deletion strain
pthresh <- 0.05 # p-value cutoff for identifying differentially-expressed genes in deletion strain
qthresh <- 0.05 # quantile cutoff for selecting similar deletion strains

# Find similar strains in Deleteome
matchingStrains <- getDeleteomeMatchesByReciprocalCorrelation(delData = alldata,
                                                              mutant=mutantname, 
                                                              minAbsLog2FC = Mthresh, 
                                                              pCutoff = pthresh, 
                                                              quantileCutoff = qthresh
                                                              )

# Show correlated mutants
message("\nSimilar mutant strains:")
print(matchingStrains)

# Generate heatmap for significantly correlated deleteome mutants
# First get a data frame that contains all the log2 fold-change and p-value info for the mutant strain 
# (AKA its "profile")
mutantProfile <- getProfileForDeletion(delData = alldata, 
                                       deletionname = mutantname, 
                                       Mthresh = Mthresh, 
                                       pthresh = pthresh)

# Generate heatmap for significantly similar deleteome profiles
hm1 <- makeHeatmapDeleteomeMatches(mutantname = mutantname, 
                                   mutantProfile, 
                                   matchingStrains, 
                                   fileprefix = "Corr_matches", 
                                   titledesc="transcriptional similarity (reciprocal correlation)", 
                                   MthreshForTitle = Mthresh, 
                                   pthreshForTitle = pthresh,
                                   quantileForTitle = qthresh,
                                   printToFile = T)

# Generate heatmap for significantly correlated deleteome strains that only shows subtelomeric genes
# NOTE: if there are less than 2 subtelomeric genes in the strain's signature, 
# this will generate an error indicating insufficient rows or columns for the heatmap
hm2 <- makeHeatmapDeleteomeMatches(mutantname = mutantname, 
                                   mutantProfile, 
                                   matchingStrains, 
                                   fileprefix = "Corr_matches_subtelo", 
                                   titledesc="transcriptional similarity (reciprocal correlation)", 
                                   MthreshForTitle = Mthresh, 
                                   pthreshForTitle = pthresh,
                                   quantileForTitle = qthresh,
                                   subteloGenesOnly = T, 
                                   rowFontSize=0.275, 
                                   printToFile = T)

# Generate heatmap using specific deleteome profiles
hm3 <- makeHeatmapDeleteomeMatches(mutantname = mutantname, 
                                   mutantProfile, 
                                   c("hmo1","rif1","sir4","ctf8","ctf18","dcc1"), 
                                   fileprefix = "Specific_mutants", 
                                   titledesc="manual selection", 
                                   MthreshForTitle = Mthresh, 
                                   pthreshForTitle = pthresh,
                                   quantileForTitle = qthresh,
                                   imagewidth = 2000,
                                   printToFile = T)


# Make a mountain lake plot (this also reports subtelomeric enrichment p-values for the mutant's up- and down-regulated genes)
makeGenomicPositionHistogram(delData = alldata, 
                             mutant = mutantname, 
                             Mthresh = Mthresh, 
                             xmax=770, ymax = 40, 
                             upcolor="#d53e4f", 
                             downcolor="#3288bd")


# Run GO enrichment on similar mutants
GOpadjcutoff = 0.05
GO <- doGOenrichmentOnDeleteomeMatches(delData = alldata, 
                                       genes = matchingStrains, 
                                       padjthresh = GOpadjcutoff)
GOoutputfile <- paste0(scriptloc,"/output/GO_enrichment/", mutantname, "_GOenrichmentResults_Corr_GOpadj",GOpadjcutoff,".tsv")
write.table(GO, file=GOoutputfile, sep="\t", quote = F, row.names = F)
message("Wrote GO enrichment results to ", GOoutputfile)
