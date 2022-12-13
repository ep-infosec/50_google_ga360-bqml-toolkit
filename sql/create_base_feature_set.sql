# /***********************************************************************
# Copyright 2020 Google Inc.
#
# Licensed under the Apache License, Version 2.0 (the 'License');
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an 'AS IS' BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# Note that these code samples being shared are not official Google
# products and are not formally supported.
# ************************************************************************/

-- Note that this query aggregates behavior on a user level without concern for when the behvior occured within
-- the time period given. Due to the nature of how converters vs. non-converters are labeled and aggregatd,
-- this may introduce some bias into the model. This model was written with the goal of of balancing simplicity, 
-- efficiency and robustness of the model, and as such, your mileage may vary depending on your specific use case.

WITH 
  visitors_labeled as ( 
  select clientId, 
  min(case when totals.transactions >= 1 then visitStartTime end) as event_session, -- Find the visit start time of the first target event; if you want the most recent, change to max()
  min(case when totals.transactions >= 1 then date end) as event_date, --  Find the date of the first target event; if you want the most recent, change to max()
  max(case when totals.transactions >= 1 then 1 else 0 end) as label -- Label each user based on the target or not
  from `{ga_data_ref}` a
  where 
  _TABLE_SUFFIX BETWEEN '{start_date}' AND '{end_date}'
  AND geoNetwork.Country="United States"
  GROUP BY clientId
  ),

-- Finds the dma with the most visits for each user. If it's a tie, arbitrarily picks one.
  visitor_city AS (
  SELECT
    clientId, metro AS dma
  FROM (
    SELECT c.clientId,c.metro, ROW_NUMBER() OVER (PARTITION BY c.clientId ORDER BY visits DESC) AS row_num
    FROM (
      SELECT a.clientId, geoNetwork.metro AS metro, COUNT(*) AS visits
      FROM `{ga_data_ref}` a
      left join visitors_labeled b
      on a.clientId = b.clientId
      where 
  _TABLE_SUFFIX BETWEEN '{start_date}' AND '{end_date}'
  AND geoNetwork.Country="United States"
      and (a.visitStartTime < IFNULL(event_session, 0)
      or event_session is null)
      GROUP BY clientId,metro ) c )
  WHERE row_num = 1 ),
  
-- Finds the daypart with the most pageviews for each user; adjusts for timezones and daylight savings time, loosely
  visitor_common_daypart AS (
  SELECT clientId, daypart
  FROM (
    SELECT clientId, daypart, ROW_NUMBER() OVER (PARTITION BY clientId ORDER BY pageviews DESC) AS row_num
    FROM (
      SELECT
        clientId,
        CASE WHEN hour_of_day_localized >= 1 AND hour_of_day_localized < 6 THEN 'night_1_6' 
        WHEN hour_of_day_localized >= 6 AND hour_of_day_localized < 11 THEN 'morning_6_11' 
        WHEN hour_of_day_localized >= 11 AND hour_of_day_localized < 14 THEN 'lunch_11_14' 
        WHEN hour_of_day_localized >= 14 AND hour_of_day_localized < 17 THEN 'afternoon_14_17' 
        WHEN hour_of_day_localized >= 17 AND hour_of_day_localized < 19 THEN 'dinner_17_19' 
        WHEN hour_of_day_localized >= 19 AND hour_of_day_localized < 22 THEN 'evening_19_23' 
        WHEN hour_of_day_localized >= 22 OR hour_of_day_localized = 0 THEN 'latenight_23_1'
        END AS daypart, SUM(pageviews) AS pageviews
      FROM (
        SELECT a.clientId, EXTRACT(HOUR
          FROM (
              CASE WHEN c.dst = 1 AND date BETWEEN '20170312' AND '20171105' THEN TIMESTAMP_ADD(TIMESTAMP_SECONDS(visitStartTime), INTERVAL c.timezone+1 HOUR) 
              WHEN c.dst = 1 AND date BETWEEN '20180311' AND '20181104' THEN TIMESTAMP_ADD(TIMESTAMP_SECONDS(visitStartTime), INTERVAL c.timezone+1 HOUR)
              WHEN c.dst = 1 AND date BETWEEN '20190310' AND '20191103' THEN TIMESTAMP_ADD(TIMESTAMP_SECONDS(visitStartTime), INTERVAL c.timezone+1 HOUR)
              WHEN c.dst = 1 AND date BETWEEN '20200308' AND '20201101' THEN TIMESTAMP_ADD(TIMESTAMP_SECONDS(visitStartTime), INTERVAL c.timezone+1 HOUR)
              ELSE TIMESTAMP_ADD(TIMESTAMP_SECONDS(visitStartTime), INTERVAL c.timezone HOUR)
              END ) ) AS hour_of_day_localized,
          totals.pageviews AS pageviews
        FROM `{ga_data_ref}` a
        LEFT JOIN ( SELECT states.*
                    FROM UNNEST ([STRUCT("Alaska" as state_name, -9 as timezone, 1 as dst),
                      STRUCT("American Samoa" as state_name, -10 as timezone, 0 as dst),
                      STRUCT("Hawaii" as state_name, -10 as timezone, 0 as dst),
                      STRUCT("California" as state_name, -7 as timezone, 1 as dst),
                      STRUCT("Idaho" as state_name, -7 as timezone, 1 as dst),
                      STRUCT("Nevada" as state_name, -8 as timezone, 1 as dst),
                      STRUCT("Oregon" as state_name, -8 as timezone, 1 as dst),
                      STRUCT("Washington" as state_name, -8 as timezone, 1 as dst),
                      STRUCT("Arizona" as state_name, -7 as timezone, 0 as dst),
                      STRUCT("Colorado" as state_name, -7 as timezone, 1 as dst),
                      STRUCT("Kansas" as state_name, -6 as timezone, 1 as dst),
                      STRUCT("Montana" as state_name, -7 as timezone, 1 as dst),
                      STRUCT("North Dakota" as state_name, -6 as timezone, 1 as dst),
                      STRUCT("Nebraska" as state_name, -6 as timezone, 1 as dst),
                      STRUCT("New Mexico" as state_name, -7 as timezone, 1 as dst),
                      STRUCT("South Dakota" as state_name, -6 as timezone, 1 as dst),
                      STRUCT("Texas" as state_name, -6 as timezone, 1 as dst),
                      STRUCT("Utah" as state_name, -7 as timezone, 1 as dst),
                      STRUCT("Wyoming" as state_name, -7 as timezone, 1 as dst),
                      STRUCT("Alabama" as state_name, -6 as timezone, 1 as dst),
                      STRUCT("Arkansas" as state_name, -6 as timezone, 1 as dst),
                      STRUCT("Florida" as state_name, -5 as timezone, 1 as dst),
                      STRUCT("Iowa" as state_name, -6 as timezone, 1 as dst),
                      STRUCT("Illinois" as state_name, -6 as timezone, 1 as dst),
                      STRUCT("Indiana" as state_name, -5 as timezone, 1 as dst),
                      STRUCT("Kentucky" as state_name, -5 as timezone, 1 as dst),
                      STRUCT("Louisiana" as state_name, -6 as timezone, 1 as dst),
                      STRUCT("Michigan" as state_name, -5 as timezone, 1 as dst),
                      STRUCT("Minnesota" as state_name, -6 as timezone, 1 as dst),
                      STRUCT("Missouri" as state_name, -6 as timezone, 1 as dst),
                      STRUCT("Mississippi" as state_name, -6 as timezone, 1 as dst),
                      STRUCT("Oklahoma" as state_name, -6 as timezone, 1 as dst),
                      STRUCT("Tennessee" as state_name, -5 as timezone, 1 as dst),
                      STRUCT("Wisconsin" as state_name, -6 as timezone, 1 as dst),
                      STRUCT("Connecticut" as state_name, -5 as timezone, 1 as dst),
                      STRUCT("District of Columbia" as state_name, -5 as timezone, 1 as dst),
                      STRUCT("Delaware" as state_name, -5 as timezone, 1 as dst),
                      STRUCT("Georgia" as state_name, -5 as timezone, 1 as dst),
                      STRUCT("Massachusetts" as state_name, -5 as timezone, 1 as dst),
                      STRUCT("Maryland" as state_name, -5 as timezone, 1 as dst),
                      STRUCT("Maine" as state_name, -5 as timezone, 1 as dst),
                      STRUCT("North Carolina" as state_name, -5 as timezone, 1 as dst),
                      STRUCT("New Hampshire" as state_name, -5 as timezone, 1 as dst),
                      STRUCT("New Jersey" as state_name, -5 as timezone, 1 as dst),
                      STRUCT("New York" as state_name, -5 as timezone, 1 as dst),
                      STRUCT("Ohio" as state_name, -5 as timezone, 1 as dst),
                      STRUCT("Pennsylvania" as state_name, -5 as timezone, 1 as dst),
                      STRUCT("Rhode Island" as state_name, -5 as timezone, 1 as dst),
                      STRUCT("South Carolina" as state_name, -5 as timezone, 1 as dst),
                      STRUCT("Virginia" as state_name, -5 as timezone, 1 as dst),
                      STRUCT("Vermont" as state_name, -5 as timezone, 1 as dst),
                      STRUCT("West Virginia" as state_name, -5 as timezone, 1 as dst),
                      STRUCT("Puerto Rico" as state_name, -4 as timezone, 0 as dst),
                      STRUCT("Virgin Islands" as state_name, -4 as timezone, 0 as dst)]) states) c
        ON a.geoNetwork.region = c.state_name
        left join visitors_labeled b
        on a.clientId = b.clientId
        where 
  _TABLE_SUFFIX BETWEEN '{start_date}' AND '{end_date}'
  AND geoNetwork.Country="United States"
        and (a.visitStartTime < IFNULL(event_session, 0)
        or event_session is null)
         )
      GROUP BY 1, 2 ) )
  WHERE row_num = 1 ),

-- Finds the most common day based on pageviews
  visitor_common_day AS (
  SELECT clientId, case when day = 1 then "Sunday"
  when day = 2 then "Monday"
  when day = 3 then "Tuesday"
  when day = 4 then "Wednesday"
  when day = 5 then "Thursday"
  when day = 6 then "Friday"
  when day = 7 then "Saturday" end as day
  FROM (
    SELECT clientId, day, ROW_NUMBER() OVER (PARTITION BY clientId ORDER BY pages_viewed DESC) AS row_num
    FROM (
      SELECT a.clientId, EXTRACT(DAYOFWEEK FROM PARSE_DATE('%Y%m%d',date)) AS day, SUM(totals.pageviews) AS pages_viewed
      FROM `{ga_data_ref}` a
      left join visitors_labeled b
      on a.clientId = b.clientId
      where 
  _TABLE_SUFFIX BETWEEN '{start_date}' AND '{end_date}'
  AND geoNetwork.Country="United States"
      and (a.visitStartTime < IFNULL(event_session, 0)
      or event_session is null)
      GROUP BY clientId, day ) )
  WHERE row_num = 1 )

-- Join tables defined above onto session data
select z.*, b.dma as visited_dma,
c.daypart as visited_daypart,
d.day as visited_dow
from (
SELECT a.clientId,
max(label) as label,
count(distinct visitId) as total_sessions,
sum(totals.pageviews) as pageviews,
count(totals.bounces)/count(distinct VisitID) as bounce_rate,
sum(totals.pageviews) / count(distinct VisitID) as avg_session_depth,
max(case when device.isMobile is True then 1 else 0 end) as mobile,
max(case when device.browser = "Chrome" then 1 else 0 end) as chrome,
max(case when device.browser like  "%Safari%" then 1 else 0 end) as safari,
max(case when device.browser <> "Chrome" and device.browser not like "%Safari%" then 1 else 0 end) as browser_other,
max(case when trafficSource.medium = '(none)' then 1 else 0 end) as visits_traffic_source_none,
max(case when trafficSource.medium = 'organic' then 1 else 0 end) as visits_traffic_source_organic,
max(case when trafficSource.medium = 'cpc' then 1 else 0 end) as visits_traffic_source_cpc,
max(case when trafficSource.medium = 'cpm' then 1 else 0 end) as visits_traffic_source_cpm,
max(case when trafficSource.medium = 'affiliate' then 1 else 0 end) as visits_traffic_source_affiliate,
max(case when trafficSource.medium = 'referral' then 1 else 0 end) as visits_traffic_source_referral,
count(distinct geoNetwork.metro) as distinct_dmas,
count(distinct EXTRACT(DAYOFWEEK FROM PARSE_DATE('%Y%m%d', date))) as num_diff_days_visited
from `{ga_data_ref}` a
left join visitors_labeled b
on a.clientId = b.clientId
where 
_TABLE_SUFFIX BETWEEN '{start_date}' AND '{end_date}'
AND geoNetwork.Country="United States"
and (a.visitStartTime < IFNULL(event_session, 0)
or event_session is null)
group by a.clientId) z
left join visitor_city b 
on z.clientId = b.clientId
left join visitor_common_daypart c 
on z.clientId = c.clientId
left join visitor_common_day d
on z.clientId = d.clientId
