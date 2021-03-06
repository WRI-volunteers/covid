/* Agregate covid case data to district level */

/**********/
/* Deaths */
/**********/
use $covidpub/covid/covid_deaths_recoveries, clear

/* keep only the deaths */
keep if patientstatus == "Deceased"

/* create counter to get total number of deaths */
gen new_deaths = 1

/* collapse to district-day */
collapse (sum) new_deaths, by(pc11_state_id pc11_district_id date)

/* save as a tempfile */
save $tmp/deaths

/*********/
/* Cases */
/*********/
use $covidpub/covid/covid_cases_raw, clear

/* rename date announced to simply date */
ren dateannounced date

/* create counter to get total number of cases */
gen new_cases = 1

/* collapse to district-day */
collapse (sum) new_cases, by(pc11_state_id pc11_district_id date)


/*******************/
/* Merge and Clean */
/*******************/
merge 1:1 pc11_state_id pc11_district_id date using $tmp/deaths

/* fill in missing new_cases and new_deaths with 0 */
replace new_cases = 0 if mi(new_cases)
replace new_deaths = 0 if mi(new_deaths)

/* create a numeric datetime */
gen datenum =  clock(date, "DMY")

/* sort by state, district, and date */
sort pc11_state_id pc11_district_id datenum

/* count the running total of cases*/
bys pc11_state_id pc11_district_id: gen total_cases = sum(new_cases)

/* count the running total of deaths */
bys pc11_state_id pc11_district_id: gen total_deaths = sum(new_deaths)

drop _merge datenum

/***************************************************************************/
/* Transform into a square dataset with district positive cases and deaths */
/***************************************************************************/

/* drop if we have no date-- hard to know what to do with these */
drop if mi(date)

/* set a missing value for missing districts so they get counted */
replace pc11_district_id = "-99" if mi(pc11_district_id)

/* create a single variable for state-district */
egen sdgroup = group(pc11_state_id pc11_district_id)

/* create a Stata date field */
ren date datestr
gen date = date(datestr, "DMY")
format date %d

/* fill in  non-reporting dates */
assert !mi(pc11_state_id) & !mi(pc11_district_id)
sort sdgroup date
fillin date sdgroup

/* fill in missing state and district ids created by the fillin */
xfill pc11_state_id, i(sdgroup)
xfill pc11_district_id, i(sdgroup)
xfill datestr, i(date)

/* create a sequential row counter so we can use L for the last seen
date even if not yesterday (fillin solves some of this but some dates
had no reporting at all. */
sort sdgroup date
by sdgroup: egen row = seq()

/* set as time series on the row */
sort sdgroup row
xtset sdgroup row

/* fill in zeroes with the new missing data */
replace new_cases = 0 if mi(new_cases)
replace new_deaths = 0 if mi(new_deaths)

/* fill in the cumulative count for days when nothing happened */
replace total_cases = 0  if datestr == "30/01/2020" & mi(total_cases)
replace total_deaths = 0 if datestr == "30/01/2020" & mi(total_deaths)
replace total_cases = L.total_cases if mi(total_cases)
replace total_deaths = L.total_deaths if mi(total_deaths)

/* drop unused fields */
drop _fillin datestr sdgroup row

/* save total case and death data */
save $covidpub/covid/covid_cases_deaths_district, replace
cap mkdir $covidpub/covid/csv
export delimited $covidpub/covid/csv/covid_cases_deaths_district.csv, replace

/* review number of confirmed/deaths in unknown districts */
sum total_* if date == 22029
sum total_* if date == 22029 & pc11_district_id == "-99"
