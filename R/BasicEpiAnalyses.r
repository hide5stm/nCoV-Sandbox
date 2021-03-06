##' Make a ggplot object that shows the age distirbution of cases
##' with indicator for living or dead.
##'
##' @param data the nCoV data to run on. Assued to have age categories.
##'
##' @return a ggplot object showing the age distribution of cases
##'
age_dist_graph <- function (data) {
  require(ggplot2)
  rc <- ggplot(drop_na(data, age_cat),
           aes(x=age_cat, fill=as.factor(death))) +
    geom_bar( color="grey") + coord_flip() + xlab("Age Catergory")

  return(rc)

}

##' Make the epi curve of reported cases. With living and
##' dead indicated.
##'
##' @param data the nCov data to run on
##'
##' @return a ggplot object showing the epidemiologic curve.
##'
epi_curve_reported_cases <- function(data) {
  ggplot(data, aes(x=symptom_onset, fill=as.factor(death))) +
    geom_bar()
}


##'
##' Make a table capturing the odds ratio of death by geneder
##'
##' @param data
##'
##' @return a data frame with includein colums with OR and CI
##'
OR_table_gender <- function(data) {
  gender_odds <- data%>%group_by(gender, death)%>%
    summarize(n())%>%
    mutate(death=ifelse(death,"dead","alive"))%>%
    pivot_wider(names_from = death,values_from=`n()`)

  #%>%
  #mutate(OR=dead/alive)

  #gender_odds <- gender_odds%>%mutate(OR=OR/gender_odds$OR[1])
  gender_odds_mdl <- glm(death~gender, data=data,
                         family=binomial)
  gender_odds$OR <- c(1, exp(gender_odds_mdl$coef[2]))
  gender_odds$CI <- c("-",
                      paste(round(exp(confint(gender_odds_mdl)[,2]),2),
                            collapse = ","))
  return(gender_odds)
}


##'
##' Make a table capturing the odds ratio of death by age cat
##'
##' @param data the data inclding an age_cat column
##' @param combine_CIs should we combine the confidence intervals
##'    into a single entry, or hav two separate columns
##'
##' @return a data frame with includein colums with OR and CI
##'
OR_table_age <- function(data, combine_CIs=TRUE) {
  age_odds <- data %>%
    drop_na(age_cat)%>%
    group_by(age_cat,death)%>%
    summarize(n())%>%
    mutate(death=ifelse(death,"dead","alive"))%>%
    pivot_wider(names_from = death,values_from=`n()`) %>%
    replace_na(list(dead=0))

  if ("(50,60]"%in%data$age_cat) {
    data$age_cat <- relevel(data$age_cat, ref="(50,60]")
  } else {
    data$age_cat <- relevel(data$age_cat, ref="50-59")
  }

  age_odds_mdl <- glm(death~age_cat, data=data,
                      family=binomial)

  n_coefs <- length(age_odds_mdl$coef)
  age_odds$OR <- c(exp(age_odds_mdl$coef[2:6]),1,
                   exp(age_odds_mdl$coef[7:n_coefs]))

  if (combine_CIs) {
    tmp <- round(exp(confint(age_odds_mdl)),2)
    tmp <- apply(tmp, 1, paste, collapse=",")
    age_odds$CI <- c(tmp[2:6],"-",tmp[7:n_coefs])
  } else {
      tmp <-exp(confint(age_odds_mdl))
      age_odds$CI_low = c(tmp[2:6,1],1,tmp[7:n_coefs,1])
      age_odds$CI_high = c(tmp[2:6,2],1,tmp[7:n_coefs,2])
  }

  return(age_odds)

}



##'
##' Function to fit monotonically increasing spline. Returns a function that 
##' can be used to predict the spline for each date. 
##' 
##' 
##' @param dates dates of observations
##' @param obs the observations
##' @param df degrees of freedon. 
##' 
##' @return a function that takse in some number of dates and gives predictions on those
##' 
fit_ispline <- function (dates, obs, df=round(length(obs)/3)) {
  require(nnls)
  require(splines2)
  
  #first get the basis
  h <- iSpline(as.numeric(dates), df=df, intercept=T)
  
  
  #fit the nnls model to the data
  mdl <- nnls(h, obs)
  coefs <- coef(mdl)
  
  
  rc <- function(dates) {
    if(length(dates)==0) {return(NULL)}
    hnew <- predict(h, as.numeric(dates))
     return(hnew%*%coefs)
  }
  
  return(rc)
}


##'
##' Function to extract approximate epidemic curves
##' from the cumulative case data.
##'
##' @param cum_data a data frame with cumulative case data in oit
##' @param first_date the first date to infer
##' @param second_date the last date to infer...shold be iwthin data range
##'
##'
##' @return a data frame with roughly estimated incidence in it
##'
est_daily_incidence <- function (cum_data,
                                 first_date,
                                 last_date,
                                 na_to_zeros=FALSE) {
  if (na_to_zeros) {
    analyze <-   cum_data %>% replace(is.na(.), 0)
  } else {
    analyze <-   cum_data %>% drop_na(Confirmed)
  }
 

  ##Get the implied daily incidence for each province
  ##by fitting a monitonically increasing spline and then
  ##taking the difference (a little less sensitive to
  ##perturbations in reporting than taking raw difference).
  ##Making sure only to infer over trhe suport
  tmp_dt_seq <- seq(first_date, last_date, "days")
  incidence_data<- analyze %>% nest(-Province_State) %>%
    mutate(cs=map(data, ~fit_ispline(dates=.$Update, obs=.$Confirmed))) %>%
    mutate(Incidence=map2(cs,data, ~data.frame(Date=tmp_dt_seq[tmp_dt_seq>=min(.y$Update) & tmp_dt_seq<=max(.y$Update)],
                                               Incidence= diff(c(0, pmax(0,.x(tmp_dt_seq[tmp_dt_seq>=min(.y$Update) & tmp_dt_seq<=max(.y$Update)]))))))) %>%
    unnest(Incidence) %>% select(-data) %>% select(-cs)
  
  return(incidence_data)
  
  #####OLD VERSION 
  # tmp_dt_seq <- seq(first_date, last_date, "days")
  # incidence_data<- analyze %>% nest(-Province_State) %>%
  #   mutate(cs=map(data, ~splinefun(x=.$Update, y=.$Confirmed,
  #                                  method="hyman"))) %>%
  #   mutate(Incidence=map2(cs,data, ~data.frame(Date=tmp_dt_seq[tmp_dt_seq>=min(.y$Update) & tmp_dt_seq<=max(.y$Update)],
  #                                              Incidence= diff(c(0, pmax(0,.x(tmp_dt_seq[tmp_dt_seq>=min(.y$Update) & tmp_dt_seq<=max(.y$Update)]))))))) %>%
  #   unnest(Incidence) %>% select(-data) %>% select(-cs)

  return(incidence_data)

}


##'
##' Function to extract approximate epidemic curves
##' from the cumulative case data.
##'
##' @param cum_data a data frame with cumulative case data in oit
##' @param first_date the first date to infer
##' @param second_date the last date to infer...shold be iwthin data range
##'
##'
##' @return a data frame with roughly estimated incidence in it
##'
est_daily_deaths <- function (cum_data,
                                 first_date,
                                 last_date,
                              na_to_zeros=FALSE) {
  
  if (na_to_zeros) {
    analyze <-   cum_data %>% replace(is.na(.), 0)
  } else {
    analyze <-   cum_data %>% drop_na(Deaths)
  }

  ##Get the implied daily incidence for each province
  ##by fitting a monitonically increasing spline and then
  ##taking the difference (a little less sensitive to
  ##perturbations in reporting than taking raw difference).
  ##Making sure only to infer over trhe suport
  tmp_dt_seq <- seq(first_date, last_date, "days")
  death_data<- analyze %>% nest(-Province_State) %>%
    mutate(cs=map(data, ~fit_ispline(dates=.$Update, obs=.$Deaths))) %>%
    mutate(Deaths=map2(cs,data, ~data.frame(Date=tmp_dt_seq[tmp_dt_seq>=min(.y$Update) & tmp_dt_seq<=max(.y$Update)],
                                               Deaths= diff(c(0, pmax(0,.x(tmp_dt_seq[tmp_dt_seq>=min(.y$Update) & tmp_dt_seq<=max(.y$Update)]))))))) %>%
    unnest(Deaths) %>% select(-data) %>% select(-cs)

  return(death_data)

}




##'
##' Function to extract approximate epidemic curves
##' from the cumulative case data.
##'
##' @param cum_data a data frame with cumulative case data in oit
##' @param first_date the first date to infer
##' @param last_date the last date to infer...shold be iwthin data range
##' @param na_to_zeros
##'
##'
##' @return a data frame with roughly estimated incidence in it
##'
est_daily_recovered <- function (cum_data,
                              first_date,
                              last_date,
                              na_to_zeros=FALSE) {
    if (na_to_zeros) {
        analyze <-   cum_data %>% replace(is.na(.), 0)
    } else {
        analyze <-   cum_data %>% drop_na(Recovered)
    }

  ##Get the implied daily incidence for each province
  ##by fitting a monitonically increasing spline and then
  ##taking the difference (a little less sensitive to
  ##perturbations in reporting than taking raw difference).
  ##Making sure only to infer over trhe suport
  tmp_dt_seq <- seq(first_date, last_date, "days")
  recovered_data<- analyze %>% nest(-Province_State) %>%
    mutate(cs=map(data, ~ fit_ispline(dates=.$Update, obs=.$Recovered))) %>%
    mutate(Incidence=map2(cs,data, ~data.frame(Date=tmp_dt_seq[tmp_dt_seq>=min(.y$Update)],
                                               Recovered= diff(c(0, pmax(0,.x(tmp_dt_seq[tmp_dt_seq>=min(.y$Update)]))))))) %>%
    unnest(Incidence) %>% select(-data) %>% select(-cs)

  return(recovered_data)

}



##' 
##' Function to automate the comparison of MERS-CoV deaths with
##' that from the Kudos line list.
##' 
##' 
##' @param kudos the data from the kudos line list.
##' 
##' @return a list with a data frame of results and a ggplot object.
##' 
compare_deaths_to_MERS <- function (kudos) {
  mers_dat <- read_csv("data/MERSDeathPublic.csv", 
                       col_types = cols(age_class=col_factor(levels = c("0-9", "10-19", "20-29", "30-39", "40-49", "50-59", "60-69", "70+"))))
  
  ##make look like the kudos dat enough for us to run same table
  mers_dat <- mers_dat %>% rename(death=died) %>% 
    rename(age_cat=age_class)
  
  mers_OR_tbl <- OR_table_age(mers_dat, combine_CIs = FALSE)
  
  #make the nCoV table look like the MERS one for a more direct 
  #comparison.
  
  kudos <- kudos %>% 
    mutate(age_cat=cut(age,breaks=c(0,10,20,30,40,50,60,70,1000),
                       labels=c("0-9","10-19",
                                "20-29","30-39",
                                "40-49","50-59",
                                "60-69","70+")))
  
  
  age_OR_tbl <- OR_table_age(kudos, combine_CIs = FALSE)
  
  ##Replace observations with no data wiht NAs
  no_data_index <- which(age_OR_tbl$dead==0)
  age_OR_tbl$OR[no_data_index] <- NA
  age_OR_tbl$CI_low[no_data_index] <- NA
  age_OR_tbl$CI_high[no_data_index] <- NA
  
  ##combine to plot
  comb_OR_tbl <- bind_rows(nCoV=age_OR_tbl,
                           MERS=mers_OR_tbl, .id="disease")
  
  comb_OR_tbl$label <- sprintf("%1.2f (%1.2f, %1.2f)", 
                               comb_OR_tbl$OR,
                               comb_OR_tbl$CI_low,
                               comb_OR_tbl$CI_high)
  comb_OR_tbl$label[comb_OR_tbl$OR==1] <- NA
  
  mers_comp_plt <- ggplot(comb_OR_tbl, aes(x=age_cat, y=OR, color=disease, label=label)) +
    geom_pointrange(aes(ymin=CI_low, ymax=CI_high),
                    position = position_dodge2(width = 0.5, padding = 0.5)) +
    scale_y_log10() + ylab("OR of death")+
    xlab("Age") +
    theme_bw()
  
  comb_OR_wide <- comb_OR_tbl %>% 
    select(disease,age_cat,label) %>% 
    pivot_wider(names_from=disease, values_from = label) 
  
  comb_OR_wide[6,c("nCoV","MERS")] <- "1"
  comb_OR_wide$nCoV[no_data_index] <- "-"
  
  return(list(plt = mers_comp_plt, table = comb_OR_wide))
}


##'
##' Function to correct for the changes in reporting in Hubei
##'
##' @param cumdat data frame with the cumulative number of cases
##' @param first_date the first date to infer incidence over
##' @param last_date  the latest date to infer incidence over
##' 
##' @return a version of the inferred incidence data corrected for reportin changes.
##' 
correct_for_Hubei_reporting <- function (cum_data, first_date, last_date, tol=100) {
 
  ## Reduce to just Hubei and drop the 13th, keeping track of it for later
  cum_data <- cum_data %>% filter(Province_State=="Hubei")
  confirmed_13 <- (cum_data %>% filter(as.Date(Update)==as.Date("2020-02-13")))$Confirmed
  cum_data_no13 <- filter(cum_data, as.Date(Update)!=as.Date("2020-02-13"))

  ## Fit the incidence curve to all data but the 13th...inferring for all days.
  incidence_data <- est_daily_incidence(cum_data_no13,
                                        first_date,
                                        last_date)
  
  ## Now get the difference between the inferred confirmed 13 and the actual
  inferred_13_smth <- filter(incidence_data, as.Date(Date)==as.Date("2020-02-13"))$Incidence
  inferred_13_cum_data <- confirmed_13 - sum((incidence_data %>% filter(Date<"2020-02-13"))$Incidence)
  diff_inferred <- inferred_13_cum_data - inferred_13_smth

  ## Keep the incidence that we want to return
  rc_incidence <- incidence_data
    
  while (diff_inferred>tol) {
    to_add <- (incidence_data %>% filter(Date<"2020-02-13"))$Incidence
    to_add <- to_add/sum(to_add) * diff_inferred
    rc_incidence$Incidence[1:length(to_add)] <- 
      rc_incidence$Incidence[1:length(to_add)]+ to_add
    
    ## create a new cumsum data
    tmp_cum_data <- data_frame(Update = rc_incidence$Date,
                             Confirmed = cumsum(rc_incidence$Incidence),
                             Province_State = as.factor("Hubei"))
    rc_incidence <- est_daily_incidence(tmp_cum_data,
                                          first_date,
                                          last_date)
    
    inferred_13_smth <- filter(rc_incidence, as.Date(Date)==as.Date("2020-02-13"))$Incidence
    
    inferred_13_cum_data <- confirmed_13 - 
      sum((rc_incidence %>% filter(Date<"2020-02-12"))$Incidence)
    
    diff_inferred <- inferred_13_cum_data - inferred_13_smth
    
    print(diff_inferred)
  }
  
  return(rc_incidence)
}


##'
##' Function to correct for the changes in reporting in Hubei
##'
##' @param cumdat data frame with the cumulative number of cases
##' @param first_date the first date to infer incidence over
##' @param last_date  the latest date to infer incidence over
##' 
##' @return a version of the inferred incidence data corrected for reportin changes.
##' 
correct_for_Hubei_reporting_1314 <- function (cum_data, first_date, last_date, tol=100) {
  
  ## Reduce to just Hubei and drop the 13th, keeping track of it for later
  cum_data <- cum_data %>% filter(Province_State=="Hubei") %>% arrange(Update)
  confirmed_1314 <- (cum_data %>% filter(as.Date(Update)==as.Date("2020-02-13") | as.Date(Update)==as.Date("2020-02-14")))
  confirmed_1314 <- (confirmed_1314 %>% mutate(Date=as.Date(Update)) %>% group_by(Date) %>% filter(Update==max(Update)) %>% ungroup())$Confirmed # get 1 per day
  cum_data_no1314 <- filter(cum_data, as.Date(Update)!=as.Date("2020-02-13") & as.Date(Update)!=as.Date("2020-02-14"))
  
  ## Fit the incidence curve to all data but the 13th or 14th...inferring for all days.
  incidence_data <- est_daily_incidence(cum_data_no1314,
                                        first_date,
                                        last_date)
  
  ## Now get the difference between the inferred confirmed 13th and 14th and the actual
  inferred_1314_smth <- filter(incidence_data, as.Date(Date)==as.Date("2020-02-13") | as.Date(Date)==as.Date("2020-02-14"))$Incidence
  # Get inferred incidence (to minimize)
  inferred_13_cum_data <- confirmed_1314[1] - sum((incidence_data %>% filter(Date<"2020-02-13"))$Incidence)
  inferred_14_cum_data <- confirmed_1314[2] - sum((incidence_data %>% filter(Date<"2020-02-13"))$Incidence) - inferred_13_cum_data
  
  # Get number needed to redistribute from each day
  diff_inferred <- (inferred_13_cum_data - inferred_1314_smth[1]) + (inferred_14_cum_data - inferred_1314_smth[2])

  ## Keep the incidence that we want to return
  rc_incidence <- incidence_data
  
  while (diff_inferred>tol) {
    to_add <- (incidence_data %>% filter(Date<"2020-02-13"))$Incidence
    to_add <- to_add/sum(to_add) * diff_inferred
    rc_incidence$Incidence[1:length(to_add)] <- rc_incidence$Incidence[1:length(to_add)] + to_add
    
    ## create a new cumsum data
    tmp_cum_data <- data_frame(Update = rc_incidence$Date,
                               Confirmed = cumsum(rc_incidence$Incidence),
                               Province_State = as.factor("Hubei"))
    rc_incidence <- est_daily_incidence(tmp_cum_data,
                                        first_date,
                                        last_date)
    
    
    ## Now get the difference between the inferred confirmed 13th and 14th and the actual
    inferred_1314_smth <- filter(rc_incidence, as.Date(Date)==as.Date("2020-02-13") | as.Date(Date)==as.Date("2020-02-14"))$Incidence
    # Difference
    inferred_13_cum_data <- confirmed_1314[1] - sum((rc_incidence %>% filter(Date<"2020-02-13"))$Incidence)
    inferred_14_cum_data <- confirmed_1314[2] - sum((rc_incidence %>% filter(Date<"2020-02-13"))$Incidence) - inferred_13_cum_data
    diff_inferred <- (inferred_13_cum_data - inferred_1314_smth[1]) + (inferred_14_cum_data - inferred_1314_smth[2])
    
    print(diff_inferred)
  }
  
  return(rc_incidence)
}



##'
##' Wrapper function to correct for the changes in reporting in Hubei and merge with data for all incidence
##'
##' @param cum_data   data frame with the cumulative number of cases
##' @param first_date the first date to infer incidence over
##' @param last_date  the latest date to infer incidence over
##' 
##' @return a corrected version of the inferred incidence data corrected for reporting changes in Hubei.
##' 
est_daily_incidence_corrected <- function(cum_data, first_date, last_date, tol=100, na_to_zeros=FALSE){
  
  ## Get estimated daily incidence for all provinces
  incid_uncorr <- est_daily_incidence(cum_data, first_date, last_date, na_to_zeros)
  
  ## Get estimated and corrected daily incidence for Hubei
  incid_hubei_corr <- correct_for_Hubei_reporting(cum_data, first_date, last_date, tol)

  ## Merge these, keeping the corrected Hubei incidence estimates.
  incid_data <- bind_rows(incid_uncorr %>% 
                            filter(!(Province_State == "Hubei" & Date <= max(incid_hubei_corr$Date))),
                          incid_hubei_corr)
  
  return(incid_data)
}




##'
##' Function to plot the estimated and reported case counts
##'
##' @param conf_cases Confirmed case data from JHU CSSE
##' @param incid_ests Estimated incidence 
##' @param locations  Locations to plot, can be a vector
##' 
##' @return a corrected version of the inferred incidence data corrected for reporting changes in Hubei.
##'
plot_incidence_ests_report <- function(conf_cases=jhucsse, incid_ests=incidence_data, locations="Hubei"){
  
  incid_ests <- incid_ests %>% mutate(Incidence = ceiling(Incidence)) %>% filter(Province_State %in% locations)
  incid_ests$Date <- as.Date(incid_ests$Date, "%m/%d/%Y")
  
  # Make conf_cases daily
  # Get daily calculated incidence (from reporting)
  conf_cases_daily <- conf_cases %>% filter(Province_State %in% locations & !is.na(Confirmed)) %>%
    mutate(Date = as.Date(Update)) %>% group_by(Province_State, Date) %>% filter(Update == max(Update, na.rm=TRUE)) %>% ungroup()
  conf_cases_daily <- conf_cases_daily %>% group_by(Province_State) %>% arrange(Date) %>% mutate(Incidence = diff(c(0, Confirmed))) %>% ungroup()
  
  # Merge in reported incidence
  incid_data_ <- left_join(incid_ests, conf_cases_daily %>% rename(Incid_rep = Incidence), by=c("Province_State", "Date")) %>% as_tibble()
  
  # Plot
  p <- ggplot(incid_data_, aes(x=Date, y=Incidence)) + 
    geom_bar(stat = "identity", fill="maroon") +
    geom_point(aes(x=Date, y=Incid_rep), col="navyblue") +
    coord_cartesian(xlim=c(as.Date("2020-01-15"), max(as.Date(incid_data_$Date)))) +
    theme_classic()
  
  if (length(locations)>1){
    p <- p + facet_wrap(vars(Province_State), nrow=7, ncol=6)
  }  
  
  plot(p)
}
