-- Tables
SELECT * FROM customer_nodes ;
SELECT * FROM regions ;
SELECT * FROM customer_transactions ;

-- A. Customer Nodes Exploration
-- 1. How many unique nodes are there on the Data Bank system?
WITH cte AS(
SELECT region_id,
COUNT(DISTINCT node_id)
FROM customer_nodes
GROUP BY region_id)
SELECT 
	SUM(count) AS total_nodes
FROM cte ;

-- 2.What is the number of nodes per region?
SELECT n.region_id,
r.region_name, 
COUNT(DISTINCT n.node_id) AS total_nodes
FROM customer_nodes n 
LEFT JOIN regions r
ON n.region_id = r.region_id
GROUP BY n.region_id, r.region_name ;

-- 3. How many customers are allocated to each region?
SELECT customer_id, 
	MAX(start_date) AS start_date
FROM customer_nodes 
GROUP BY customer_id ;


-- 4. How many days on average are customers reallocated to a different node?
WITH cte AS(
SELECT *, 
	end_date - start_date AS days_in_node
FROM customer_nodes 
WHERE end_date != '9999-12-31'
ORDER BY customer_id)
SELECT ROUND(AVG(days_in_node),1) AS avg_in_a_nodes
FROM cte ;


-- 5. What is the median, 80th and 95th percentile for this same reallocation days metric for each region?
WITH stat AS(
SELECT *, 
	end_date - start_date AS days_in_node
FROM customer_nodes 
WHERE end_date != '9999-12-31'
ORDER BY customer_id)
SELECT
	percentile_disc(0.5) WITHIN GROUP (ORDER BY days_in_node) AS median,
	percentile_disc(0.8) WITHIN GROUP (ORDER BY days_in_node) AS p80,
	percentile_disc(0.95) WITHIN GROUP (ORDER BY days_in_node) AS p95
FROM stat ;

-- B. Customer Transactions
-- 1. What is the unique count and total amount for each transaction type?
SELECT 
	txn_type AS transactions_type,
	COUNT(txn_type) AS transactions_count, 
	SUM(txn_amount) AS transactions_amount
FROM customer_transactions 
GROUP BY txn_type 
ORDER BY transactions_count DESC ;

-- 2. What is the average total historical deposit counts and amounts for all customers?
SELECT 
	DISTINCT customer_id AS user,
	COUNT(txn_type) AS count_deposit,
	ROUND( AVG(txn_amount), 2) AS avg_deposit
FROM customer_transactions 
WHERE txn_type = 'deposit'
GROUP BY customer_id
ORDER BY count_deposit DESC ;

-- 3. For each month - how many Data Bank customers make more than 1 deposit 
-- and either 1 purchase or 1 withdrawal in a single month?
WITH cte AS(
SELECT  
	EXTRACT(month from txn_date) AS month,
	customer_id,
	SUM(CASE WHEN txn_type = 'deposit' THEN 1 END) as deposit_count,
	SUM(CASE WHEN txn_type = 'withdrawal' THEN 1 END) as withdrawal_count,
	SUM(CASE WHEN txn_type = 'purchase' THEN 1 END) as purchase_count	
FROM customer_transactions
GROUP BY month, customer_id, txn_type
ORDER BY month)
SELECT *
FROM cte 
WHERE deposit_count >= 1 
	AND (withdrawal_count >= 1 OR purchase_count >= 1) 
;

-- 4. What is the closing balance for each customer at the end of the month?
WITH summary AS(
SELECT  
	EXTRACT(month from txn_date) AS month,
	customer_id,
	CASE WHEN txn_type = 'deposit' THEN SUM(txn_amount) ELSE 0 END as deposit_count,
	CASE WHEN txn_type = 'withdrawal' THEN SUM(txn_amount) ELSE 0 END as withdrawal_count,
	CASE WHEN txn_type = 'purchase' THEN SUM(txn_amount) ELSE 0 END as purchase_count	
FROM customer_transactions
GROUP BY month, customer_id, txn_type
ORDER BY month),
monthly AS(
SELECT 
	month,
	customer_id,
	SUM(deposit_count) AS deposit,
	SUM(withdrawal_count) AS withdrawal,
	SUM(purchase_count) AS purchase
FROM summary
GROUP BY month, customer_id
ORDER BY month, customer_id)
SELECT 
	month,
	customer_id,
	deposit - (withdrawal + purchase) AS balance
FROM monthly
ORDER BY month, customer_id
;


-- 5. What is the percentage of customers who increase their closing balance by more than 5%?
WITH balance_per_month AS (
    SELECT
        customer_id,
        DATE_TRUNC('month', txn_date) AS month,
        SUM(CASE WHEN txn_type = 'deposit' THEN txn_amount
                 WHEN txn_type IN ('withdrawal', 'purchase') THEN -txn_amount
                 ELSE 0 END) AS monthly_net
    FROM customer_transactions
    GROUP BY customer_id, DATE_TRUNC('month', txn_date)
),
closing_balance AS (
    SELECT
        customer_id,
        month,
        SUM(monthly_net) OVER (PARTITION BY customer_id ORDER BY month) AS closing_balance
    FROM balance_per_month
),
balance_change AS (
    SELECT
        customer_id,
        month,
        closing_balance,
        LAG(closing_balance) OVER (PARTITION BY customer_id ORDER BY month) AS prev_balance
    FROM closing_balance
),
growth_check AS (
    SELECT
        month,
        COUNT(*) FILTER (WHERE closing_balance > prev_balance) AS increased,
        COUNT(*) FILTER (WHERE prev_balance IS NOT NULL) AS total_customers
    FROM balance_change
    GROUP BY month
)
SELECT 
    month,
    increased,
    total_customers,
    CASE 
        WHEN total_customers = 0 THEN 0
        ELSE ROUND(100.0 * increased / total_customers, 2)
    END AS percent_increased
FROM growth_check
ORDER BY month;

-- Tables
SELECT * FROM customer_nodes ;
SELECT * FROM regions ;
SELECT * FROM customer_transactions ;