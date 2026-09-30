
-- ============================================================================
--  PROJECT   : RCB IPL Strategy Analysis


--  DATABASE  : ipl
--  PURPOSE   : Analytical SQL queries supporting a data-driven player
--              retention / auction strategy for Royal Challengers
--              Bangalore (RCB), built on the IPL ball-by-ball dataset.


--  -----
--  Team_Id = 2 refers to Royal Challengers Bangalore throughout this file.
--  All queries are validated against the schema created in ipl_merged.sql
--    (tables: Player, Ball_by_Ball, Matches, Player_Match, Wicket_Taken,
--    Team, Venue, Season, Bowling_Style, Batting_Style, etc.)
--   Section 1  -> Objective Questions   (Q1  - Q15)
--   Section 2  -> Subjective/Strategic Analysis (Q1 - Q10)
-- ============================================================================

USE ipl;


-- ============================================================================
-- SECTION 1: OBJECTIVE QUESTIONS
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Q1  List the different dtypes of columns in table “ball_by_ball” (using information schema) 
SELECT  
	COLUMN_NAME, DATA_TYPE  
FROM  
	INFORMATION_SCHEMA.COLUMNS  
WHERE TABLE_NAME = 'ball_by_ball'; 

-- Q2. What is the total number of runs scored in 1st season by RCB (bonus: also include the extra runs using the extra runs table)
SELECT
	SUM(b.Runs_Scored + COALESCE(e.Extra_Runs,0))AS Total_Runs_With_Extras
FROM
	Ball_by_Ball b
	JOIN Matches m ON b.Match_Id = m.Match_Id
	LEFT JOIN Extra_Runs e ON b.Match_Id = e.Match_Id AND b.Over_Id = e.Over_Id AND b.Ball_Id = e.Ball_Id AND b.Innings_No = e.Innings_No
WHERE 
	m.Season_Id = 6 AND b.Team_Batting = (SELECT Team_Id
											FROM Team
											WHERE Team_Name = 'Royal Challengers Bangalore');
    
-- Q3. How many players were more than the age of 25 during season 2014?
SELECT 
	COUNT(DISTINCT p.player_id) as Total_player_above25 
FROM 
	player p
INNER JOIN player_match pm ON p.player_id = pm.player_id
INNER JOIN matches m ON m.match_id = pm.match_id
WHERE TIMESTAMPDIFF(YEAR,p.dob,'2014-01-01') >25
 AND m.season_id = (SELECT season_id FROM season WHERE season_year='2014');   

-- Q4. How many matches did RCB win in 2013? 
	SELECT
		COUNT(*) AS Matches_Won_By_RCB
	FROM
		Matches m
	JOIN Season s ON m.Season_Id = s.Season_Id
	WHERE
		s.Season_Year = 2013 AND m.Match_Winner = (SELECT Team_Id
														FROM Team
														WHERE Team_Name = 'Royal Challengers Bangalore'
												);
    -- Q5. List the top 10 players according to their strike rate in the last 4 seasons
WITH last4_seasons AS (
    SELECT s.Season_Id
    FROM season s
    ORDER BY s.Season_Id DESC
    LIMIT 4
),
recent_matches AS (
    SELECT m.Match_Id
    FROM matches m
    WHERE m.Season_Id IN (SELECT Season_Id FROM last4_seasons)
)
SELECT 
    p.Player_Id AS player_id,
    p.Player_Name AS player_name,
    ROUND(100.0 * SUM(b.Runs_Scored) / COUNT(b.Runs_Scored),2) AS strike_rate
FROM player p
JOIN ball_by_ball b ON b.Striker = p.Player_Id
WHERE b.Match_Id IN (SELECT Match_Id FROM recent_matches)
AND NOT EXISTS (
    SELECT 1
    FROM extra_runs e
    WHERE b.Match_Id = e.Match_Id
      AND b.Over_Id = e.Over_Id
      AND b.Ball_Id = e.Ball_Id
      AND e.Extra_Type_Id NOT IN(1,3)
      AND b.Innings_No = e.Innings_No
) 
GROUP BY p.Player_Id, p.Player_Name
HAVING COUNT(b.Runs_Scored) >= 500
ORDER BY strike_rate DESC
LIMIT 10;
 
-- Q6. What are the average runs scored by each batsman considering all the seasons?
SELECT
    p.Player_Name,
    -- SUM(sub.Total_Runs) AS Total_Runs,
--     COUNT(*) AS Innings_Played,
    ROUND(SUM(sub.Total_Runs) * 1.0 / COUNT(*), 2) AS Avg_Runs
FROM
    (
        SELECT
            Striker,
            Match_Id,
            Innings_No,
            SUM(Runs_Scored) AS Total_Runs
        FROM
            Ball_by_Ball
        GROUP BY
            Striker, Match_Id, Innings_No
    ) AS sub
JOIN Player p ON p.Player_Id = sub.Striker
GROUP BY
    p.Player_Name
ORDER BY
    Avg_Runs DESC;
 
 -- Q7. What are the average wickets taken by each bowler considering all the seasons?
 SELECT 
    p.player_name,
    COUNT(wt.player_out) / COUNT(DISTINCT m.season_id) AS avg_wickets_per_season
FROM 
    player p
JOIN 
    ball_by_ball b ON b.bowler = p.player_id
JOIN 
    wicket_taken wt ON wt.match_id = b.match_id AND wt.over_id = b.over_id AND wt.ball_id = b.ball_id
JOIN 
    matches m ON m.match_id = b.match_id
GROUP BY 
    p.player_name
ORDER BY 
    avg_wickets_per_season DESC;

-- Q8 List all the players who have average runs scored greater than the overall average and who have taken wickets greater than the overall average
WITH player_runs AS (
SELECT
Striker AS Player_Id,
SUM(Runs_Scored) AS Total_Runs,
COUNT(DISTINCT CONCAT(Match_Id, '-', Innings_No)) AS Innings_Played
FROM
Ball_by_Ball
GROUP BY
Striker
),
player_avg_runs AS (
SELECT
Player_Id,
ROUND(Total_Runs * 1.0 / Innings_Played, 2) AS Avg_Runs
FROM
player_runs
WHERE Innings_Played > 0
),
overall_avg_runs AS (
SELECT
ROUND(AVG(Total_Runs * 1.0 / Innings_Played), 2) AS Overall_Avg_Runs
FROM
player_runs
WHERE Innings_Played > 0
),
player_wickets AS (
SELECT
b.Bowler AS Player_Id,
COUNT(w.Player_Out) AS Total_Wickets
FROM
Ball_by_Ball b
JOIN
Wicket_Taken w ON b.Match_Id = w.Match_Id
AND b.Over_Id = w.Over_Id
AND b.Ball_Id = w.Ball_Id
AND b.Innings_No = w.Innings_No
GROUP BY
b.Bowler
),
overall_avg_wickets AS (
SELECT
ROUND(AVG(Total_Wickets), 2) AS Overall_Wickets
FROM
player_wickets
)
SELECT
p.Player_Name,
r.Avg_Runs,
w.Total_Wickets
FROM
player_avg_runs r
JOIN
overall_avg_runs oar ON 1=1
JOIN
player_wickets w ON r.Player_Id = w.Player_Id
JOIN
overall_avg_wickets oaw ON 1=1
JOIN
Player p ON p.Player_Id = r.Player_Id
WHERE
r.Avg_Runs > oar.Overall_Avg_Runs
AND w.Total_Wickets > oaw.Overall_Wickets;

-- Q9. Create a table rcb_record table that shows the wins and losses of RCB in an individual venue.
-- Step 1: Create the Table:
CREATE TABLE rcb_record (
    Venue_Name VARCHAR(100),
    Wins INT DEFAULT 0,
    Losses INT DEFAULT 0
);
-- Step 2: Insert the Wins and Losses by Venue:
SELECT 
    v.Venue_Name,
    SUM(CASE WHEN m.Match_Winner = 2 THEN 1 ELSE 0 END) AS Wins,
    SUM(CASE 
            WHEN (m.Match_Winner IS NOT NULL AND m.Match_Winner != 2 AND (m.Team_1 = 2 OR m.Team_2 = 2)) 
            THEN 1 
            ELSE 0 
        END) AS Losses
FROM 
    Matches m
JOIN 
    Venue v ON m.Venue_Id = v.Venue_Id
WHERE 
    (m.Team_1 = 2 OR m.Team_2 = 2)  -- RCB participated
GROUP BY 
    v.Venue_Name
order by wins desc, losses asc;

-- Q10. What is the impact of bowling style on wickets taken?
SELECT
	bs. Bowling_skill, COUNT(wt.player_out) as Wicket_taken
FROM 
	player p
INNER JOIN bowling_style bs on p.bowling_skill = bs.bowling_id
INNER JOIN ball_by_ball bb on p.player_id = bb.bowler
INNER JOIN wicket_taken wt on bb.match_id = wt.match_id and bb.over_id = wt.over_id and bb.ball_id = wt.ball_id
GROUP BY bs.bowling_skill
ORDER BY Wicket_taken desc;

-- Q11.Write the SQL query to provide a status of whether the performance of the team is better than the previous year's performance on the basis of the number of runs scored by the team in the season and the number of wickets taken 
WITH team_runs AS (
SELECT
m.Season_Id,
b.Team_Batting AS Team_Id,
SUM(b.Runs_Scored) AS Total_Runs
FROM
Ball_by_Ball b
JOIN
Matches m ON b.Match_Id = m.Match_Id
GROUP BY
m.Season_Id, b.Team_Batting
),
team_wickets AS (
SELECT
m.Season_Id,
b.Team_Bowling AS Team_Id,
COUNT(w.Player_Out) AS Total_Wickets
FROM
Ball_by_Ball b
JOIN
Matches m ON b.Match_Id = m.Match_Id
JOIN
Wicket_Taken w ON b.Match_Id = w.Match_Id
AND b.Over_Id = w.Over_Id
AND b.Ball_Id = w.Ball_Id
AND b.Innings_No = w.Innings_No
GROUP BY
m.Season_Id, b.Team_Bowling
),
combined AS (
SELECT
r.Season_Id,
r.Team_Id,
r.Total_Runs,
w.Total_Wickets
FROM
team_runs r
JOIN
team_wickets w ON r.Season_Id = w.Season_Id AND r.Team_Id = w.Team_Id
),
with_previous AS (
SELECT
c.*,
s.Season_Year,
LAG(c.Total_Runs) OVER (PARTITION BY c.Team_Id ORDER BY s.Season_Year) AS Prev_Total_Runs,
LAG(c.Total_Wickets) OVER (PARTITION BY c.Team_Id ORDER BY s.Season_Year) AS Prev_Total_Wickets
FROM
combined c
JOIN
Season s ON c.Season_Id = s.Season_Id
)
SELECT
t.Team_Name,
wp.Season_Year,
wp.Total_Runs,
wp.Total_Wickets,
wp.Prev_Total_Runs,
wp.Prev_Total_Wickets,
CASE
WHEN wp.Total_Runs > wp.Prev_Total_Runs AND wp.Total_Wickets > wp.Prev_Total_Wickets THEN 'Improved'
WHEN wp.Total_Runs < wp.Prev_Total_Runs AND wp.Total_Wickets < wp.Prev_Total_Wickets THEN 'Declined'
ELSE 'Same'
END AS Performance_Status
FROM
with_previous wp
JOIN
Team t ON wp.Team_Id = t.Team_Id
WHERE
wp.Prev_Total_Runs IS NOT NULL AND wp.Prev_Total_Wickets IS NOT NULL
ORDER BY
t.Team_Name, wp.Season_Year;

-- Q12. Can you derive more KPIs for the team strategy? 
-- 1. Win Percentage:
SELECT 
    t.team_name,
    COUNT(CASE WHEN m.match_winner = t.team_id THEN 1 END) * 100.0 / COUNT(*) AS win_percentage
FROM 
    matches m
JOIN 
    team t ON t.team_id = m.team_1 OR t.team_id = m.team_2
GROUP BY 
    t.team_name;

-- 2.Average Runs per Match
SELECT 
    t.team_name,
    SUM(b.runs_scored) / COUNT(DISTINCT m.match_id) AS avg_runs_per_match
FROM 
    ball_by_ball b
JOIN 
    matches m ON b.match_id = m.match_id
JOIN 
    team t ON b.team_batting = t.team_id
GROUP BY 
    t.team_name
ORDER BY 
    avg_runs_per_match DESC;

-- 3. Average Wickets per Match
SELECT 
    t.team_name,
    COUNT(w.player_out) / COUNT(DISTINCT m.match_id) AS avg_wickets_per_match
FROM 
    wicket_taken w
JOIN 
    ball_by_ball b ON w.match_id = b.match_id AND w.over_id = b.over_id AND w.ball_id = b.ball_id
JOIN 
    matches m ON w.match_id = m.match_id
JOIN 
    team t ON b.team_bowling = t.team_id
GROUP BY 
    t.team_name
ORDER BY 
    avg_wickets_per_match DESC;

-- 4. Run Rate
SELECT 
    t.team_name,
    SUM(b.runs_scored) / (COUNT(DISTINCT m.match_id) * 20) AS run_rate
FROM 
    ball_by_ball b
JOIN 
    matches m ON b.match_id = m.match_id
JOIN 
    team t ON b.team_batting = t.team_id
GROUP BY 
    t.team_name
ORDER BY 
    run_rate DESC;
-- 5.Toss Impact KPI
SELECT 
    t.team_name,
    td.toss_name AS toss_decision,
    COUNT(CASE WHEN m.toss_winner = m.match_winner THEN 1 END) * 100.0 / COUNT(*) AS win_percentage_after_toss_decision
FROM 
    matches m
JOIN 
    team t ON m.toss_winner = t.team_id
JOIN 
    toss_decision td ON m.toss_decide = td.toss_id
GROUP BY 
    t.team_name, td.toss_name
ORDER BY 
    t.team_name, td.toss_name;


-- Q13.Using SQL, write a query to find out the average wickets taken by each bowler in each venue. Also, rank the gender according to the average value.
SELECT
    p.Player_Name,
    v.Venue_Name,
    AVG(wt.Player_Out) AS Average_Wickets,
    RANK() OVER (ORDER BY AVG(wt.Player_Out) DESC) AS Wicket_Rank
FROM
    player p
INNER JOIN
    player_match pm ON p.Player_Id = pm.Player_Id
INNER JOIN
    matches m ON pm.Match_Id = m.Match_Id
INNER JOIN
    wicket_taken wt ON m.Match_Id = wt.Match_Id
                     AND p.Player_Id = wt.Player_Out
INNER JOIN
    venue v ON m.Venue_Id = v.Venue_Id
GROUP BY
    p.Player_Name, v.Venue_Name
ORDER BY
    Wicket_Rank;

-- Q14. Which of the given players have consistently performed well in past seasons? (will you use any visualization to solve the problem)
-- 1. For batsman- seasonwise run scored
SELECT
p.Player_Name,
s.Season_Year,
SUM(b.Runs_Scored) AS Total_Runs
FROM
Ball_by_Ball b
JOIN Matches m ON b.Match_Id = m.Match_Id
JOIN Season s ON m.Season_Id = s.Season_Id
JOIN Player p ON b.Striker = p.Player_Id
GROUP BY
p.Player_Name, s.Season_Year
ORDER BY
p.Player_Name, s.Season_Year;

-- 2. For bowler- season wise wicket taken
SELECT
p.Player_Name,
s.Season_Year,
COUNT(w.Player_Out) AS Total_Wickets
FROM
Ball_by_Ball b
JOIN Wicket_Taken w ON b.Match_Id = w.Match_Id
AND b.Over_Id = w.Over_Id
AND b.Ball_Id = w.Ball_Id
AND b.Innings_No = w.Innings_No
JOIN Matches m ON b.Match_Id = m.Match_Id
JOIN Season s ON m.Season_Id = s.Season_Id
JOIN Player p ON b.Bowler = p.Player_Id
GROUP BY
p.Player_Name, s.Season_Year
ORDER BY
p.Player_Name, s.Season_Year;


-- Q15. Are there players whose performance is more suited to specific venues or conditions? (how would you present this using charts?) 
-- For Batsman (Runs per Venue):
SELECT 
  p.Player_Name,
    v.Venue_Name,
    SUM(b.Runs_Scored) AS Total_Runs
FROM 
    Ball_by_Ball b
JOIN Matches m ON b.Match_Id = m.Match_Id
JOIN Venue v ON m.Venue_Id = v.Venue_Id
JOIN Player p ON b.Striker = p.Player_Id
GROUP BY 
    p.Player_Name, v.Venue_Name
    order by total_runs desc
    limit 10;

-- For Bowlers (Wickets per Venue):
SELECT
p.Player_Name,
v.Venue_Name,
COUNT(w.Player_Out) AS Total_Wickets
FROM
Ball_by_Ball b
JOIN Wicket_Taken w ON b.Match_Id = w.Match_Id
AND b.Over_Id = w.Over_Id
AND b.Ball_Id = w.Ball_Id
AND b.Innings_No = w.Innings_No
JOIN Matches m ON b.Match_Id = m.Match_Id
JOIN Venue v ON m.Venue_Id = v.Venue_Id
JOIN Player p ON b.Bowler = p.Player_Id
GROUP BY
p.Player_Name, v.Venue_Name
Order by total_wickets desc
limit 10;


-- ============================================================================
-- SECTION 2: SUBJECTIVE / STRATEGIC ANALYSIS
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Q1. How does the toss decision affect the result of the match? (which visualizations could be used to present your answer better) And is the impact limited to only specific venues?
WITH Toss_Win_Stats AS (
    SELECT v.Venue_Name,
           td.Toss_Name AS Toss_Decision,
           COUNT(*) AS Total_Matches,
           SUM(CASE WHEN m.Match_Winner = m.Toss_Winner THEN 1 ELSE 0 END) AS Matches_Won_After_Toss,
           (SUM(CASE WHEN m.Match_Winner = m.Toss_Winner THEN 1 ELSE 0 END) / COUNT(*)) * 100 AS Win_Percentage
    FROM matches m
    INNER JOIN toss_decision td ON m.Toss_Decide = td.Toss_Id
    INNER JOIN venue v ON m.Venue_Id = v.Venue_Id
    GROUP BY v.Venue_Name, td.Toss_Name
)
SELECT Venue_Name,
       Toss_Decision,
       Total_Matches,
       Matches_Won_After_Toss,
       Win_Percentage
FROM Toss_Win_Stats
WHERE Total_Matches >= 10
ORDER BY Win_Percentage DESC, Total_Matches DESC;

-- Q2. Suggest some of the players who would be best fit for the team.
-- For Batsman
SELECT
p.Player_Name,
ROUND(SUM(b.Runs_Scored) * 1.0 / COUNT(DISTINCT m.Match_Id), 2) AS Avg_Runs_Per_Match
FROM
Ball_by_Ball b
JOIN Matches m ON b.Match_Id = m.Match_Id
JOIN Player p ON b.Striker = p.Player_Id
GROUP BY
p.Player_Name
HAVING COUNT(DISTINCT m.Match_Id) >= 5  -- filters out players who played too few matches
ORDER BY Avg_Runs_Per_Match DESC
LIMIT 10;

-- For bowler
SELECT
p.Player_Name,
COUNT(w.Player_Out) AS Total_Wickets
FROM
Ball_by_Ball b
JOIN Wicket_Taken w ON b.Match_Id = w.Match_Id
AND b.Over_Id = w.Over_Id
AND b.Ball_Id = w.Ball_Id
AND b.Innings_No = w.Innings_No
JOIN Player p ON b.Bowler = p.Player_Id
GROUP BY
p.Player_Name
ORDER BY Total_Wickets DESC
LIMIT 10;

-- Q3. What are some of the parameters that should be focused on while selecting the players?
WITH Player_Stats AS (
  SELECT
      p.Player_Name,
      COUNT(DISTINCT m.Match_Id) AS Matches_Played,
      -- Batting metrics
      SUM(bbb.Runs_Scored) AS Total_Runs,
      AVG(bbb.Runs_Scored) AS Avg_Runs_Per_Ball,
      (SUM(bbb.Runs_Scored) /COUNT(bbb.ball_id ))* 100.0  AS Strike_Rate,
      -- Bowling metrics
      COUNT(wt.Player_Out) AS Total_Wickets
      FROM player p
  INNER JOIN ball_by_ball bbb ON p.Player_Id = bbb.Striker OR p.Player_Id = bbb.Bowler
  INNER JOIN matches m ON bbb.Match_Id = m.Match_Id
  LEFT JOIN wicket_taken wt
         ON bbb.Match_Id = wt.Match_Id
        AND bbb.Over_Id = wt.Over_Id
        AND bbb.Ball_Id = wt.Ball_Id
  GROUP BY p.Player_Name
)
SELECT
    Player_Name,
    Matches_Played,
    Total_Runs,
    ROUND(Avg_Runs_Per_Ball, 2) AS Avg_Runs_Per_Ball,
    ROUND(Strike_Rate, 2) AS Strike_Rate,
    Total_Wickets
FROM Player_Stats
WHERE Matches_Played > 10
ORDER BY
    Total_Runs DESC
LIMIT 10;

-- Question No: 4 (Which players offer versatility in their skills and can contribute effectively with both bat and ball)
-- Step 1: Calculate batting performance
CREATE TEMPORARY TABLE IF NOT EXISTS BattingPerformance AS
SELECT
    p.Player_Name,
    SUM(bbb.Runs_Scored) AS Total_Runs,
    COUNT(bbb.Ball_Id) AS Balls_Faced
FROM player p
INNER JOIN ball_by_ball bbb ON p.Player_Id = bbb.Striker
INNER JOIN matches m ON bbb.Match_Id = m.Match_Id
GROUP BY p.Player_Name;
-- Step 2: Calculate bowling performance
CREATE TEMPORARY TABLE IF NOT EXISTS BowlingPerformance AS
SELECT
    p.Player_Name,
    COUNT(bbb.Ball_Id) AS Balls_Bowled,
    SUM(bbb.Runs_Scored) AS Runs_Conceded
FROM player p
INNER JOIN ball_by_ball bbb ON p.Player_Id = bbb.Bowler
INNER JOIN matches m ON bbb.Match_Id = m.Match_Id
GROUP BY p.Player_Name;
-- Step 3: Combine both performances and calculate metrics
SELECT
    bp.Player_Name,
    bp.Total_Runs,
    (bp.Total_Runs * 100.0 / bp.Balls_Faced) AS Strike_Rate,
    wp.Runs_Conceded,
    (wp.Runs_Conceded * 1.0 / wp.Balls_Bowled) AS Economy_Rate
FROM BattingPerformance bp
INNER JOIN BowlingPerformance wp ON bp.Player_Name = wp.Player_Name
WHERE bp.Balls_Faced > 50 AND wp.Balls_Bowled > 30
ORDER BY Strike_Rate DESC, Economy_Rate ASC
LIMIT 10;

-- Q5. Are there players whose presence positively influences the morale and performance of the team? (justify your answer using visualization) 
SELECT
Player_Name,
COUNT(*) AS Matches_Played,
SUM(CASE WHEN Team_Id = Match_Winner THEN 1 ELSE 0 END) AS Matches_Won,
ROUND(SUM(CASE WHEN Team_Id = Match_Winner THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS Win_Percentage
FROM (
SELECT DISTINCT
m.Match_Id,
p.Player_Name,
pb.Team_Batting AS Team_Id,
m.Match_Winner
FROM Ball_by_Ball pb
JOIN Matches m ON pb.Match_Id = m.Match_Id
JOIN Player p ON pb.Striker = p.Player_Id
) AS player_matches
GROUP BY Player_Name
HAVING Matches_Played >= 10
ORDER BY Win_Percentage DESC
Limit 10;

-- Q6.What would you suggest to RCB before going to the mega auction?
SELECT
	p.Player_Name,
	COUNT(DISTINCT m.Match_Id) AS Matches_Played,
	SUM(CASE WHEN m.Match_Winner = b.Team_Batting THEN 1 ELSE 0 END) AS Matches_Won,
	ROUND(SUM(CASE WHEN m.Match_Winner = b.Team_Batting THEN 1 ELSE 0 END) * 100.0 / COUNT(DISTINCT m.Match_Id), 2) AS Win_Percentage
FROM 
	Ball_by_Ball b
	JOIN Matches m ON b.Match_Id = m.Match_Id
	JOIN Player p ON b.Striker = p.Player_Id
WHERE 
	b.Team_Batting = 2
GROUP BY 
	p.Player_Name
HAVING 
	Matches_Played >= 10
ORDER BY 
	Win_Percentage DESC
LIMIT 5;

-- Q7. What do you think could be the factors contributing to the high-scoring matches and the impact on viewership and team strategies 
SELECT
v.Venue_Name,
ROUND(SUM(b.Runs_Scored) * 1.0 / COUNT(b.Ball_Id), 2) AS Avg_Runs_Per_Ball
FROM Ball_by_Ball b
JOIN Matches m ON b.Match_Id = m.Match_Id
JOIN Venue v ON m.Venue_Id = v.Venue_Id                  
GROUP BY v.Venue_Name
ORDER BY Avg_Runs_Per_Ball DESC;


-- Q8. Analyze the impact of home-ground advantage on team performance and identify strategies to maximize this advantage for RCB.
SELECT
    t.Team_Name AS Team,
    v.Venue_Name AS Home_Venue,
    COUNT(DISTINCT m.Match_Id) AS Matches_Played_At_Home,
    SUM(CASE WHEN m.Match_Winner = t.Team_Id THEN 1 ELSE 0 END) AS Wins_At_Home,
    ROUND(SUM(CASE WHEN m.Match_Winner = t.Team_Id THEN 1 ELSE 0 END) * 100.0 / COUNT(DISTINCT m.Match_Id), 2) AS Win_Percentage_At_Home
FROM Matches m
JOIN Venue v ON m.Venue_Id = v.Venue_Id
JOIN Team t ON m.Team_1 = t.Team_Id OR m.Team_2 = t.Team_Id
WHERE v.Venue_Name LIKE '%Chinnaswamy%'
AND t.team_name ='Royal Challengers Bangalore'
GROUP BY t.Team_Name, v.Venue_Name
ORDER BY Win_Percentage_At_Home DESC;


-- Q9.Come up with a visual and analytical analysis of the RCB's past season's performance and potential reasons for them not winning a trophy. 
WITH RCB_Performance AS (
    SELECT
        m.Season_Id,
        COUNT(m.Match_Id) AS Matches_Played,
        SUM(CASE WHEN m.Match_Winner = t.Team_Id THEN 1 ELSE 0 END) AS Matches_Won,
        SUM(CASE WHEN m.Match_Winner != t.Team_Id THEN 1 ELSE 0 END) AS Matches_Lost,
        (SUM(CASE WHEN m.Match_Winner = t.Team_Id THEN 1 ELSE 0 END) / COUNT(m.Match_Id)) * 100 AS Win_Percentage
    FROM matches m
    INNER JOIN team t ON t.Team_Id = m.Team_1 OR t.Team_Id = m.Team_2
    WHERE t.Team_Name = 'Royal Challengers Bangalore'
    GROUP BY m.Season_Id
)
SELECT
    s.Season_Year,
    rp.Matches_Played,
    rp.Matches_Won,
    rp.Matches_Lost,
    rp.Win_Percentage
FROM RCB_Performance rp
INNER JOIN season s ON rp.Season_Id = s.Season_Id
ORDER BY s.Season_Year;


 
-- ============================================================================
-- END OF FILE
-- ============================================================================
