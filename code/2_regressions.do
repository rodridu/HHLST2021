

global homedir "C:/Users/hongz/Downloads/Covid Exposure"
cd "${homedir}"

*-------------------------*
* Import and clean scores *
*-------------------------*
*Scores
use "output/scored.dta", clear

drop if gvkey == .
gen dateQ = qofd(date(event_date, "DMY"))
format dateQ %tq
tostring gvkey, replace
replace gvkey = "0" + gvkey if length(gvkey) == 5
replace gvkey = "00" + gvkey if length(gvkey) == 4

*If not already quarterly, take average by calendar quarter
collapse (mean) covid_exposure=normalized ///
	(first) cusip isin hq company_name sic ///
	, by(gvkey dateQ)

tempfile scores
save "`scores'", replace

*----------------------*
* Prepare stock return *
*----------------------*
use "input/stockprice/firm_stockpriceQ.dta", clear

replace return3mo = return3mo / 100

*Generate year-to-date return
xtset firm_id dateQ
gen returnY2D = .
replace returnY2D = (return3mo) if quarter(dofq(dateQ)) == 4
replace returnY2D = ((return3mo+1)*(L.return3mo+1)) - 1 if quarter(dofq(dateQ)) == 1
replace returnY2D = ((return3mo+1)*(L.return3mo+1)*(L2.return3mo+1)) - 1 if quarter(dofq(dateQ)) == 2
replace returnY2D = ((return3mo+1)*(L.return3mo+1)*(L2.return3mo+1)*(L3.return3mo+1)) - 1 if quarter(dofq(dateQ)) == 3
replace returnY2D = returnY2D*100

replace return3mo = return3mo*100
keep if yofd(dofq(dateQ)) == 2020
keep gvkey dateQ priceclose return3mo returnY2D
label var returnY2D "Year-to-day stock return: Dec 31, 2019 to today"

tempfile returns
save "`returns'", replace

*----------------*
* Merge and save *
*----------------*
use "`scores'", clear
merge 1:1 gvkey dateQ using "`returns'"
drop if _merge == 2
drop _merge
save "output/regression_data.dta", replace

*-----------------*
* Run regressions *
*-----------------*
use "output/regression_data.dta", clear

egen firm_id = group(gvkey)
gen sic2 = substr(sic, 1, 2)
egen sector_id = group(sic2)

qui su covid_exposure
gen covid_exposure_std = covid_exposure / r(sd)

est clear

*No FE
qui reghdfe return3mo covid_exposure_std ///
	, noabsorb vce(cluster firm_id)
est store a
estadd local quarterFE "no"
estadd local sectorFE "no"
estadd local firmFE "no"

*Quarter FE
qui reghdfe return3mo covid_exposure_std ///
	, absorb(i.dateQ) vce(cluster firm_id) nocons
est store b
estadd local quarterFE "yes"
estadd local sectorFE "no"
estadd local firmFE "no"

*Quarter & SIC2 FE
qui reghdfe return3mo covid_exposure_std ///
	, absorb(i.dateQ i.sector_id) vce(cluster firm_id) nocons
est store c
estadd local quarterFE "yes"
estadd local sectorFE "yes"
estadd local firmFE "no"

*Quarter & Firm FE
qui reghdfe return3mo covid_exposure_std ///
	, absorb(i.dateQ i.firm_id) vce(cluster firm_id) nocons
est store d
estadd local quarterFE "yes"
estadd local sectorFE "n/a"
estadd local firmFE "yes"

*Last quarter only
preserve
	bys gvkey: egen mean_covid_exposure = mean(covid_exposure)
	keep if dateQ == q(2020q4)
	qui su mean_covid_exposure
	gen mean_covid_exposure_std = mean_covid_exposure / r(sd)
	qui reg returnY2D mean_covid_exposure_std, vce(cluster firm_id)
	est store e
	estadd local quarterFE "n/a"
	estadd local sectorFE "n/a"
	estadd local firmFE "n/a"
restore

esttab * using "output/regtable.csv", r2 se star(* 0.1 ** 0.05 *** 0.01) ///
	scalars(quarterFE sectorFE firmFE) csv replace
