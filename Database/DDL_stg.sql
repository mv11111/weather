CREATE DATABASE WeatherDB; -- creating a database which will later be used to store all tables relevant for weather task

CREATE TABLE WeatherDB.dbo.STG_WEATHER (
    city                           VARCHAR(100) ,
    latitude                       DECIMAL(8, 6) , 
    longitude                      DECIMAL(9, 6) ,
    generation_time_ms             DECIMAL(7, 4) , 
    utc_offset_seconds             INT ,
    timezone                       VARCHAR(100) ,
    timezone_abbreviation          VARCHAR(20) ,
    elevation                      DECIMAL(5, 1) , 
    time_unit                      VARCHAR(20) ,
    temperature_2m_unit            VARCHAR(10) ,
    precipitation_unit             VARCHAR(10) ,
    relative_humidity_2m_unit      VARCHAR(10) ,
    precipitation_probability_unit VARCHAR(10) ,
    time                           VARCHAR(20) ,
    temperature_2m                 DECIMAL(4, 1) ,  
    precipitation                  DECIMAL(6, 2) ,
    relative_humidity_2m           INT NULL,           
    precipitation_probability      INT NULL,            
    ts_insert                      DATETIME2(3) DEFAULT SYSDATETIME() --just for keeping track of inserts into staging table
); -- creating a staging table which will be truncated and loaded daily, from this table we will be doing ETL into other tables in our data mart

USE WeatherDB;
GO
CREATE PROCEDURE dbo.PROC_TRUNC_STG_WEATHER 
AS 
BEGIN
    TRUNCATE TABLE WeatherDB.dbo.stg_weather;
END;
GO  -- creating a procedure to truncate STG table daily

GRANT EXECUTE ON dbo.PROC_TRUNC_STG_WEATHER to public;
GO -- granting execute to public, fastest way here, not good practice in general