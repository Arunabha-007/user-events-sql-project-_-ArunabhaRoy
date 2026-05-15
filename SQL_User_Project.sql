use user_project;

SELECT  *
FROM user_events;


-- How many total events are in the table? Also show the count for each event type.
select count(*)  as Total_Events from user_events;

select
event_type,
COUNT(*) as Event_Count
from user_events
group by event_type;

-- Find all unique users who made at least one purchase.

select distinct
user_id
from user_events
where event_type = 'purchase'
order by user_id asc

-- What is the total revenue, average order value, and number of orders?

select
USER_ID,
SUM(amount)over(partition by user_id)as Total_Revenue,
avg(amount)over(partition by user_id)as Avg_Order_Value,
COUNT(product_id) over(partition by user_id) as Order_Count
from user_events
where event_type = 'purchase';

-- How many events came from each traffic source?

select
traffic_source,
count(*) as Event_Count,
count(distinct user_id) as User_Count
from user_events
group by traffic_source
order by Event_Count

--List the top 5 products by number of page views.

select Top 5
product_id,
COUNT(*) as Product_Count
from user_events
where event_type = 'page_view'
group by product_id
order by Product_Count desc

--Build a conversion funnel: show how many unique users reached each stage (page_view → add_to_cart → checkout_start → payment_info → purchase).

select
count(distinct case when event_type = 'page_view' then user_id end) as pv_users,
count(distinct case when event_type = 'add_to_cart' then user_id end) as ac_users,
count(distinct case when event_type = 'checkout_start' then user_id end) as cs_users,
count(distinct case when event_type = 'payment_info' then user_id end) as pi_users,
count(distinct case when event_type = 'purchase' then user_id end) as p_users
from user_events

-- Which traffic source generates the most revenue? Show revenue and conversion rate (purchasers / visitors) per source.

select
traffic_source,
CAST(SUM(amount) AS DECIMAL(10)) as Revenue_Earned
from user_events
group by traffic_source;

select
count(distinct user_id) as total_user_count,
count(distinct case when event_type = 'purchase' then user_id end) as purchase_users_count,
CAST(100.0 * COUNT(DISTINCT CASE WHEN event_type = 'purchase' THEN user_id END) / NULLIF(COUNT(DISTINCT user_id), 0) AS DECIMAL(10,2)) AS conversion_rate
from user_events;

-- Find users who added a product to cart but never completed a purchase (abandoned cart users).

with users_details as(
select
USER_ID,
count(distinct case when event_type = 'add_to_cart' then user_id end) as ac_users,
count(distinct case when event_type = 'purchase' then user_id end) as p_users,
(count(distinct case when event_type = 'add_to_cart' then user_id end)) - (count(distinct case when event_type = 'purchase' then user_id end)) as User_Retain_Purcahse
from user_events
group by user_id
)
select* from users_details
where ac_users = 1 and p_users = 0
order by user_id asc

--Show daily revenue and the 7-day rolling average revenue.
with daily_rev as(
 SELECT
        CAST(event_date AS DATE)  AS sale_date,
        ROUND(SUM(amount), 2)      AS daily_rev
    FROM user_events
    WHERE event_type = 'purchase'
    GROUP BY CAST(event_date AS DATE)
)

select
sale_date,
daily_rev,
round(avg(daily_rev)over(order by sale_date rows between 6 preceding and current row),2) as day_7rolling_Avg
from daily_rev


-- For each product, calculate the view-to-purchase conversion rate.
select
product_id,
count(distinct case when event_type = 'page_view' then user_id end) as pv_users,
count(distinct case when event_type = 'purchase' then user_id end) as p_users,
CAST(
    COUNT(DISTINCT CASE WHEN event_type = 'purchase' THEN user_id END) * 100.0
    / NULLIF(COUNT(DISTINCT CASE WHEN event_type = 'page_view' THEN user_id END), 0)
AS DECIMAL(10,2)) AS Conversion_Rate
from user_events
group by product_id;

-- Rank users by total revenue spent using DENSE_RANK(). Show the top 10 customers.
with Total_Rev as (
select 
user_id,
SUM(amount) Over(partition by user_id) Total_Revenue,
DENSE_RANK() over(order by amount desc) as RN
from user_events
)
select*
from Total_Rev 
where RN between 1 and 11;

-- For each user, find their average time between page_view and purchase (in minutes) for completed journeys.

with time_diff as (
select
pv.user_id,
pv.product_id,
pv.event_date as Page_View_Date,
pu.event_date as Purchase_Date,
DATEDIFF(Minute,pv.event_date,pu.event_date) as Time_Gap
from user_events as pv
inner join user_events as pu
on pv.user_id = pu.user_id
and pv.product_id = pu.product_id
and pv.event_type = 'page_view'
and pu.event_type = 'purchase'
and pu.event_date > pv.event_date
)
select
user_id,
Count(*) user_count,
Round(AVG(1.0 * Time_Gap),1) as Avg_Gap
from time_diff
group by user_id
order by Avg_Gap;

-- Identify "high-value" users: those whose total spend is above the average spend of all buyers. Show their spend and percentile.
WITH user_spend AS (
    SELECT
        user_id,
        SUM(amount) AS total_spend
    FROM user_events
    WHERE event_type = 'purchase'
    GROUP BY user_id
),

avg_spend AS (
    SELECT AVG(total_spend) AS avg_total_spend
    FROM user_spend
)

SELECT
    us.user_id,
    us.total_spend,
    PERCENT_RANK() OVER (ORDER BY us.total_spend) AS spend_percentile,
    'high_value' AS user_rating
FROM user_spend us
CROSS JOIN avg_spend a
WHERE us.total_spend > a.avg_total_spend
ORDER BY us.total_spend DESC;

--Find the most popular product per traffic source (the product with the most page views for each source).
select*,
case 
    when Product_Count > 1500 then 'Most Popular'
    when Product_Count > 1000 then 'Popular'
    else 'Less Popular'
End as Product_Rating
from(
SELECT
    traffic_source,
    COUNT(product_id) AS Product_Count
FROM user_events
where event_type = 'page_view'
GROUP BY traffic_source
)t

--Cohort analysis: for users who first visited in each week, what % eventually made a purchase?
with cohort_batch as(
select
user_id,
DATEPART(YEAR,min(event_date)) as cohort_year,
DATEPART(Month,min(event_date)) as cohort_month
from user_events
where event_type = 'page_view'
group by user_id
),
purchase_batch as(
select
distinct user_id as purcahse_user_id
from user_events
where event_type = 'purchase'
)
select
cb.cohort_month,
cb.cohort_year,
count(cb.user_id) as cohort_users,
count(pb.purcahse_user_id) as purchase_user,
round(100*(count(cb.user_id))/count(pb.purcahse_user_id),2) as conversion_part
from purchase_batch as pb
join cohort_batch as cb
on cb.user_id = pb.purcahse_user_id
group by cb.cohort_month,cb.cohort_year
order by cb.cohort_month,cb.cohort_year