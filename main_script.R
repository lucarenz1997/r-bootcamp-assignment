  ## packages
  library(lubridate) # used to round to the next hour
  library(dplyr)
  library(readxl)
  
  # VEHICLES DF - CLEANING
  vehicles_df <- read.csv("data/vehicles.csv", header=TRUE)
  
  ## columns to be removed due to high NaN ratio.
  columns_to_remove <- c(
    "CROSS.STREET.NAME",
    "ON.STREET.NAME",
    "OFF.STREET.NAME", 
    "CONTRIBUTING.FACTOR.VEHICLE.3",
    "CONTRIBUTING.FACTOR.VEHICLE.4", 
    "CONTRIBUTING.FACTOR.VEHICLE.5",
    "VEHICLE.TYPE.CODE.3",
    "VEHICLE.TYPE.CODE.4",
    "VEHICLE.TYPE.CODE.5",
    "COLLISION_ID"
  )
  
  min_cutoff_date <- as.Date("2016-01-01")
  max_cutoff_date <- as.Date("2022-01-01")
  
  ## Create broader categories for main causes
  conditions <- c("Aggressive Driving/Road Rage", "Pavement Slippery", "Following Too Closely", 
                  "Unspecified", "", "Passing Too Closely", "Driver Inexperience", 
                  "Passing or Lane Usage Improper", "Turning Improperly", "Unsafe Lane Changing", 
                  "Unsafe Speed", "Reaction to Uninvolved Vehicle", "Steering Failure", 
                  "Traffic Control Disregarded", "Other Vehicular", "Driver Inattention/Distraction", 
                  "Oversized Vehicle", "Pedestrian/Bicyclist/Other Pedestrian Error/Confusion", 
                  "Alcohol Involvement", "View Obstructed/Limited", "Failure to Yield Right-of-Way", 
                  "Illnes", "Lost Consciousness", "Brakes Defective", "Backing Unsafely", "Glare", 
                  "Passenger Distraction", "Fell Asleep", "Obstruction/Debris", "Tinted Windows", 
                  "Animals Action", "Drugs (illegal)", "Pavement Defective", "Other Lighting Defects", 
                  "Outside Car Distraction", "Driverless/Runaway Vehicle", "Tire Failure/Inadequate", 
                  "Fatigued/Drowsy", "Headlights Defective", "Accelerator Defective", 
                  "Failure to Keep Right", "Physical Disability", "Eating or Drinking", 
                  "Cell Phone (hands-free)", "Lane Marking Improper/Inadequate", 
                  "Cell Phone (hand-Held)", "Using On Board Navigation Device", "Other Electronic Device", 
                  "Traffic Control Device Improper/Non-Working", "Tow Hitch Defective", 
                  "Windshield Inadequate", "Vehicle Vandalism", "Shoulders Defective/Improper", 
                  "Prescription Medication", "Listening/Using Headphones", "Texting", "80", 
                  "Reaction to Other Uninvolved Vehicle", "1", "Drugs (Illegal)", "Illness", 
                  "Cell Phone (hand-held)")
  
  ## mapping for conditions
  categorize_condition <- function(condition) {
    if (grepl("Driving|Following|Passing|Inexperience|Improper|Changing|Speed|Distraction|Alcohol|Drugs|Phone|Eating|Fatigued|Sleeping|Pedestrian|Failure to Yield|Backing|Oversized", condition, ignore.case = TRUE)) {
      return("Human Error")
    } else if (grepl("Brakes|Steering|Tire|Headlights|Accelerator|Windshield|Tow Hitch|Defective|Failure", condition, ignore.case = TRUE)) {
      return("Mechanical Error")
    } else if (grepl("Pavement|Glare|Obstruction|Weather|Animals|View|Control|Shoulders", condition, ignore.case = TRUE)) {
      return("Environmental Conditions")
    } else if (grepl("Illness|Lost Consciousness|Physical Disability", condition, ignore.case = TRUE)) {
      return("Medical Condition")
    } else if (condition == "" || grepl("Unspecified|Other", condition, ignore.case = TRUE)) {
      return("Other/Unspecified")
    } else {
      return("Other/Unspecified")
    }
  }
  
  vehicles_df <- vehicles_df %>%
    mutate(CRASH.DATE = as.Date(CRASH.DATE, format = "%m/%d/%Y")) %>%  # Convert CRASH.DATE to Date format
    select(-all_of(columns_to_remove)) %>%
    filter(CRASH.DATE >= min_cutoff_date) %>%
    filter(CRASH.DATE < max_cutoff_date) %>%
    filter(!is.na(LATITUDE) & !is.na(LONGITUDE)) %>%
    filter(LATITUDE != 0 | LONGITUDE != 0) %>%
    filter(!is.na(CRASH.TIME)) %>%
    ##create new column with broader category for accident
    mutate(Category = sapply(CONTRIBUTING.FACTOR.VEHICLE.1, categorize_condition)) %>%
    # Combine date and time into one string
    mutate(CRASH.DATETIME = as.POSIXct(paste(CRASH.DATE, CRASH.TIME), format = "%Y-%m-%d %H:%M")) %>%
    # Round down to the current hour
    mutate(CRASH.DATETIME = floor_date(CRASH.DATETIME, "hour")) %>%
    # enriching datetime format to weekdays, month, quarter, year
    mutate(
      Weekday = wday(CRASH.DATETIME, label = TRUE, abbr = FALSE), 
      Month = month(CRASH.DATETIME, label = TRUE, abbr = FALSE),  
      Quarter = quarter(CRASH.DATETIME),                          
      Year = year(CRASH.DATETIME) ,
      Day = day(CRASH.DATETIME),
      Hour = hour(CRASH.DATETIME),  
      TimeOfDay = case_when(                      
        Hour >= 6 & Hour < 12  ~ "Morning",
        Hour >= 12 & Hour < 17 ~ "Afternoon",
        Hour >= 17 & Hour < 20 ~ "Late Afternoon",
        Hour >= 20 ~ "Night",
        Hour < 6 ~ "Early Morning",
        TRUE ~ "Unknown",
      )
    ) %>%
    filter(!is.na(CRASH.TIME)) %>%
    mutate(IS.DEADLY.ACCIDENT = (NUMBER.OF.PERSONS.KILLED + NUMBER.OF.PEDESTRIANS.KILLED + NUMBER.OF.CYCLIST.KILLED + NUMBER.OF.MOTORIST.KILLED) > 0,
           IS.INJURED.ACCIDENT = (NUMBER.OF.PERSONS.INJURED + NUMBER.OF.PEDESTRIANS.INJURED + NUMBER.OF.CYCLIST.INJURED + NUMBER.OF.MOTORIST.INJURED) > 0)
  
  # WEATHER DF - CLEANING
  weather_df <- read_excel("data/weather.xlsx")
  weather_df <- weather_df %>%
    rename("temperature_celsius" = "temperature_2m (Â°C)", "winddirection_10m_degrees" = "winddirection_10m (Â°)") %>%
    mutate(time = as.POSIXct(time, format = "%Y-%m-%dT%H:%M")) %>% # Convert the TIME column to correct format
    filter(!is.na(time)) %>% #filter rows where there is no time 
    filter(rowSums(is.na(.)) / ncol(weather_df) < 0.8) # Filter rows where 80% or more columns are NaN/Na
  
  # MERGING DATAFRAMES
  merged_df <- left_join(vehicles_df, weather_df, by = c("CRASH.DATETIME" = "time"))
  
  write.csv(merged_df,"merged_all_years.csv")
  
  split_datasets <- split(merged_df, merged_df$Year)
  
  # Save each year to a separate file
  lapply(names(split_datasets), function(year) {
    filename <- paste0("merged_data_", year, ".csv")
    write.csv(split_datasets[[year]], file = filename, row.names = FALSE)
  })
