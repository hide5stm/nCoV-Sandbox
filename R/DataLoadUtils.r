##' Function to read in and do some minor cleaning on the
##' "Kudos" data.
##'
##' @param filename the file name
##'
##' @return a data frame with the basic data.
##'
readKudos2 <- function (filename) {
  require(tidyverse)
  rc <- read_csv(filename, col_types =
                               cols(date=col_date("%m/%d/%Y"),
                                    gender=col_factor(),
                                    symptom_onset = col_date("%m/%d/%Y")))

  return(rc)
}

##' Same as above but for older Kudos file layout.
readKudos <- function (filename) {
    require(tidyverse)
    rc <- read_csv(filename, col_types =
                                 cols(Date=col_date("%m/%d/%Y"),
                                      Gender=col_factor(),
                                      `Symptom onset (approximate)` = col_date("%m/%d/%Y")))

                                        #extract death data
    rc <- mutate(rc, dead=str_detect(Summary,"death")) %>%
        rename(onset=`Symptom onset (approximate)`)

    return(rc)
}

##'
##' Reads in the JHUCSSE total case count data up
##' until (and including) a given dat.
##'
##' @param last_time the last time to consider data from
##' @param append_wiki sjpi;d we also append data from wikipedia.
##'
##' @return a data frame with the basic data.
##'
read_JHUCSSE_cases <- function(last_time, append_wiki) {

  ## first get a list of all of the files in the directory
  ## starting with "JHUCSSE Total Cases"
  file_list <- list.files("data","JHUCSSE Total Cases",
                          full.names = TRUE)

  file_list <- rev(file_list)

  ##Now combine them into one data frame
  rc <- NULL

  for (file in file_list) {
    tmp <- read_csv(file)%>%
      rename(Province_State=`Province/State`)%>%
      rename(Update = `Last Update`) %>%
      mutate(Update=lubridate::parse_date_time(Update, c("%m/%d/%Y %I:%M %p", "%m/%d/%Y %H:%M", "%m/%d/%y %I:%M %p")))

    if("Country"%in%colnames(tmp)) {
      tmp <- rename(tmp, Country_Region=Country)
    } else {
      tmp <- rename(tmp, Country_Region=`Country/Region`)
    }

    rc <-bind_rows(rc,tmp)
  }

  ##Now drop any after the date given
  rc <- rc%>%filter(Update<=last_time) %>%
    mutate(Country_Region=replace(Country_Region, Country_Region=="China", "Mainland China")) %>%
    mutate(Country_Region=replace(Country_Region, Province_State=="Macau", "Macau")) %>%
    mutate(Country_Region=replace(Country_Region, Province_State=="Hong Kong", "Hong Kong")) %>%
    mutate(Country_Region=replace(Country_Region, Province_State=="Taiwan", "Taiwan"))

  if (append_wiki) {
    wiki <- read_csv("data/WikipediaWuhanPre1-20-2020.csv",
                     col_types=cols(Update = col_datetime("%m/%d/%Y")))
    rc <-bind_rows(rc,wiki)
  }

  return(rc)
}

##' grabs linelist from Kudos
##' and saves as csv if we want
##' NOTE: need to test with with the loading functions..
##' @param auto_save_csv
##' @return
read_kudos_direct <- function(auto_save_csv=TRUE){
    library(googlesheets4)
    library(readr)
    library(lubridate)
    ## note this will break if sheet name changes or structure changes
    ll_sheet <- read_sheet("https://docs.google.com/spreadsheets/d/1jS24DjSPVWa4iuxuD4OAXrE3QeI8c9BC1hSlqr-NMiU/edit#gid=1187587451",
                           sheet="Line-list",skip=1,na="NA") %>%
        mutate(`reporting date` = as_date(`reporting date`))

    ## some fields are coming out as a list. Probably a better way to manage but...
    ll_sheet[,"age"] <- Reduce("c",ll_sheet$age) %>% as.numeric
    ll_sheet[,"symptom_onset"] <- Reduce("c",ll_sheet$symptom_onset) %>% as_date
    ll_sheet[,"If_onset_approximated"] <- Reduce("c",ll_sheet$If_onset_approximated)
    ll_sheet[,"hosp_visit_date"] <- Reduce("c",ll_sheet$hosp_visit_date) %>% as_date
    ll_sheet[,"exposure_start"] <- Reduce("c",ll_sheet$exposure_start) %>% as_date
    ll_sheet[,"exposure_end"] <- Reduce("c",ll_sheet$exposure_end) %>% as_date
    ll_sheet[,"from Wuhan"] <- Reduce("c",ll_sheet$`from Wuhan`)


    if(auto_save_csv){
        file_name <- paste0("data/Kudos Line List-",Sys.Date() %>% format("%m-%d-%y"),".csv")
        cat(sprintf("saving file as %s \n",file_name))
        write_csv(ll_sheet %>% as.data.frame,file_name)
    }

    return(ll_sheet)
}
