#This is the script for the paper "Sentinel-2 time series: a promising tool in monitoring individual species phenology and its variability"  
#It includes: 
# 1) indices time series pre-processing and outlier removing 
# 2) modelling indices time series using GAM (for a single year)
# 3) SOS detection using derivatives technique
# you can use the example "mtci_example.csv" file 

#required packages 
packages_list = c("tidyverse", "tsibble", "bfast", "data.table", "mgcv","forecast", "anytime")
lapply(packages_list, require, character.only = TRUE)

#1) Indices time series pre-processing and outlier removing (on .csv format acquired from GEE)

#df is as csv format containing variables (in this particular order): date, index value, sample (pixel) unique ID, species
df =  read.csv("path to file")

#actually there is one (first) unnecessary column in mtci_ex.csv with row id so just remove it:
df = df[,-1]

#now first column called system.index should be converted to date format
df$system.index = as.Date(df$system.index, format =  "%Y%m%d")

#and let's change column names 
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


gam_deriv = function(id_no, input_df, year){
  options(warn=-1)
  df = input_df %>%
    filter(date > paste(year, "03-15", sep = "-") & 
             date < paste(year, "11-20", sep = "-")) %>%
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
  model = gamm(df_tibble[,2] ~ s(date, k = 16), 
               data = df_tibble, method = "REML")
  #predicting values using GAM model
  df_tibble$predicted = predict.gam(model$gam, df_tibble)
  derivative = diff(df_tibble$predicted)/diff(df_tibble$date)
  der = cbind(df_tibble[-1,"date"], round(derivative,4)) %>% as.data.frame()
  names(der) = c("date", paste(id_no))
  der_long = der %>%
    gather("id", "value", 2:length(der))
  sos = der_long %>% 
    slice(which.max(value))
  sos = sos[,c("date", "id")]
  names(sos) = c("SOS", "id")
  #change date format to DOY
  sos$SOS = anydate(sos$SOS) %>% strftime(format = "%j") %>% as.numeric()
  sos$species = df$species[1]
  return(sos)
}

#gam_deriv example for single pixel:
sos_single = gam_deriv(id_no = 3199, input_df = df_clean, year = "2018")

#Example for many/all pixels:

#firstly, create a vector  of unique pixel IDs for analyzed year
#only when minimum number of observations during the year is 16)

year = "2018"
single_year = df_clean %>%
  filter(date > paste(year, "03-15", sep = "-") & 
           date < paste(year, "11-20", sep = "-"))

IDs = single_year %>%
  dplyr::count(id) %>%
  dplyr::filter(n > 16) %>%
  distinct(id) %>%
  pull(id)

#then calculate gam_deriv function for all pixels using lapply
start = Sys.time()
sos_multi = lapply(IDs[1:100], gam_deriv, single_year, "2018") %>%
  rbindlist()
end = Sys.time()
end-start

#sos visualization example 
ggplot(sos_multi, aes(SOS, species))+
  geom_boxplot()+
  xlim(100, 160)

write.csv2(sos_multi, "path")
