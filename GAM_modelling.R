#This is the script for the paper "Sentinel-2 time series: a promising tool in monitoring individual species phenology and its variability"  
#It includes: 
# 1) indices time series pre-processing and outlier removing 
# 2) modelling indices time series using GAM
# you can use the example "mtci_example.csv" file 

#required packages 
packages_list = c("tidyverse", "tsibble", "bfast", "data.table", "mgcv","forecast", "anytime")
lapply(packages_list, require, character.only = TRUE)

#1) Indices time series pre-processing and outlier removing (on .csv format acquired from GEE)

#df is as csv format tab;e containing variables (in this particular order): date, index value, sample (pixel) unique ID, species
df =  read.csv("F:/phenology_Sentinel2/mtci_2018_2022.csv")

#first column converter to date
df$system.index = as.Date(df$system.index, format =  "%Y%m%d")

#change column names 
names(df) = c("date", "index", "id", "species")

#filtering - removing NA and high/low values
df_clean = df %>% 
  drop_na() %>%
  group_by(date, species, id) %>%
  summarise(index = mean(index)) %>% 
  ungroup() %>%
  dplyr::filter(index > 0 & index < 8) %>% #in case of MTCI 0;8 EVI 0;1 NDVI 0;1
  arrange(date)


#2) Modelling time series and detecting SOS/EOS based on derivatives for a single year--------

#gam_deriv is a function to model time series for each pixel 
#using GAM and detecting SOS dates based on derivatives
#id_no is unique pixel ID, input_df is filtered dataframe and year is selected year (a character)

unique(sel$id)
input_df = df_clean
id_no = 596


#function to model time series using GAM and detecting SOS dates based on derivatives
gam_model = function(id_no, input_df){
  options(warn=-1)
  df = input_df %>%
    filter(id == id_no) 
  df_ts = df[,"index"] %>% #step of identifying and replacing outliers (i.e. "index" column)
    ts() %>%
    tsclean(iterate = 2) %>%
    as.data.frame()
  #creating regular (1-day) time series with NA for missing values
  df_bfast = bfastts(df_ts$index, df$date, type = ("irregular"))
  #creating dataframe with proper date format
  df_tibble = tibble(date = seq(as.Date(df$date[1]), by = "day", 
                                length.out = length(df_bfast)), value = df_bfast) %>%
    as_tsibble(index = date) %>%
    ts() %>% 
    as.data.frame()
  #gam modelling with dates as predictor, 
  model = gamm(df_tibble[,2] ~ s(date, k = 80), 
               data = df_tibble, method = "REML")
  #predicting values using GAM model
  df_tibble$predicted = predict.gam(model$gam, df_tibble)
  df_gam = df_tibble[,c("date", 'predicted')] 
  df_gam$id = id_no
  df_gam$species = df$species[1]
  df_gam$date = anydate(df_gam$date)
  return(df_gam)
}



#gam_model example for single pixel:
gam_single = gam_model(id_no = 3199, input_df = df_clean)

#and plot:
ggplot(gam_single, aes(date, predicted))+
  geom_line()



#Example for many pixels:

#firstly, create a vector  of unique pixel IDs for analyzed year
#only when minimum number of observations during this period is e.g. 80)

IDs = df_clean %>%
  dplyr::count(id) %>%
  dplyr::filter(n > 80) %>%
  distinct(id) %>%
  pull(id)



#then calculate gam_deriv function for all pixels using lapply
start = Sys.time()
gam_multi = lapply(IDs[1:100], gam_model, df_clean) %>%
  rbindlist()
end = Sys.time()
end-start

#sos visualization example 
ggplot(gam_multi, aes(date, predicted, group = id, color = species))+
  geom_line()

write.csv2(gam_multi, "path")