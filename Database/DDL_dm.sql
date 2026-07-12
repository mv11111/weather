USE WeatherDB;
GO

--dimensions

--date dimension
CREATE TABLE dbo.DIM_DATE (
    date_key       INT NOT NULL PRIMARY KEY, -- Primary Key (Format: YYYYMMDD)
    full_date      DATE NOT NULL,
    day_of_week    INT NOT NULL,
    day_name       VARCHAR(10) NOT NULL,
    month          INT NOT NULL,
    month_name     VARCHAR(10) NOT NULL,
    quarter        INT NOT NULL,
    year           INT NOT NULL
);

--location dimension
CREATE TABLE dbo.DIM_LOCATION (
    location_key          INT IDENTITY(1,1) NOT NULL PRIMARY KEY, -- Surrogate Key
    city                  VARCHAR(100) NOT NULL,
    latitude              DECIMAL(8, 6) NOT NULL, 
    longitude             DECIMAL(9, 6) NOT NULL,
    elevation             DECIMAL(5, 1) NOT NULL,
    timezone_name         VARCHAR(100) NULL,
    timezone_abbreviation VARCHAR(20) NULL,
    date_from             DATE NOT NULL,
    date_to               DATE NOT NULL
);

--unit of measurement dimension
CREATE TABLE dbo.DIM_UNIT (
    unit_key              INT IDENTITY(1,1) NOT NULL PRIMARY KEY, -- Surrogate Key
    temperature_unit      VARCHAR(10) NULL,
    precipitation_unit    VARCHAR(10) NULL,
    humidity_unit         VARCHAR(10) NULL
);
GO

--fact table

CREATE TABLE dbo.FACT_WEATHER_FORECAST (
    date_key                  INT NOT NULL,
    location_key              INT NOT NULL,
    unit_key                  INT NOT NULL,
    
    temperature_2m            DECIMAL(4, 1) NULL,
    precipitation             DECIMAL(6, 2) NULL,
    relative_humidity_2m      INT NULL,
    precipitation_probability INT NULL,
    utc_offset_seconds        INT NULL,
    
    -- primary key, one row per date per location
    CONSTRAINT PK_fact_weather_forecast 
        PRIMARY KEY CLUSTERED (date_key, location_key),
    
    -- FKs, rows need to exist in dimension tables
    CONSTRAINT FK_fact_weather_date 
        FOREIGN KEY (date_key) REFERENCES dbo.dim_date(date_key),
        
    CONSTRAINT FK_fact_weather_location 
        FOREIGN KEY (location_key) REFERENCES dbo.dim_location(location_key),
        
    CONSTRAINT FK_fact_weather_unit 
        FOREIGN KEY (unit_key) REFERENCES dbo.dim_unit(unit_key)
);
GO

--- dimension procedures

CREATE PROCEDURE dbo.PROC_POPULATE_DIM_DATE
AS 
    DECLARE @startdate datetime
    DECLARE @enddate datetime
    SET @startdate = DATEFROMPARTS(2024,1,1)
    SET @enddate = DATEFROMPARTS(2028,1,1)
    DECLARE @loopdate datetime
    SET @loopdate = @startdate
    
    WHILE @loopdate <= @enddate
        BEGIN
            INSERT INTO dbo.dim_date VALUES (
            CONVERT(int, CONVERT(char(8), @loopdate, 112)),
            @loopdate, 
            DATEPART(dw,@loopdate),
            DATENAME(dw,@loopdate),
            MONTH(@loopdate),
            DATENAME(month,@loopdate), 
            DATEPART(q,@loopdate),
            YEAR(@loopdate)
            ) 
            SET @loopdate = DATEADD(d, 1, @loopdate)
        END;
GO  

GRANT EXECUTE ON dbo.PROC_POPULATE_DIM_DATE to public;
GO -- granting execute to public, fastest way here, not good practice in general

-----

CREATE PROCEDURE dbo.PROC_POPULATE_DIM_LOCATION
AS 
 
BEGIN
    DECLARE @Today DATE = CAST(SYSDATETIME() AS DATE);
    DECLARE @Yesterday DATE = DATEADD(DAY, -1, @Today);
    DECLARE @MaxDate DATE = DATEFROMPARTS(9999,12,31);

    -- first - closing old rows if there are any changes in the staging table

    UPDATE target
    SET target.date_to = @Yesterday
    FROM dbo.dim_location target
    LEFT JOIN dbo.STG_WEATHER source
        ON target.city = source.city
    WHERE target.date_to = @MaxDate -- Only look at currently active rows
      AND (
      source.city is null -- added later to close rows that arent fetched from the source
        OR   target.latitude != source.latitude
        OR target.longitude != source.longitude
        OR target.elevation != source.elevation
        OR ISNULL(target.timezone_name, '') != ISNULL(source.timezone, '')
        OR ISNULL(target.timezone_abbreviation, '') != ISNULL(source.timezone_abbreviation, '')
        
      );

    -- second - inserting new rows if new cities appeared or if there was a change in existing ones
    INSERT INTO dbo.dim_location (
        city, latitude, longitude, elevation, 
        timezone_name, timezone_abbreviation, date_from, date_to
    )
    SELECT 
        source.city, source.latitude, source.longitude, source.elevation, 
        source.timezone, source.timezone_abbreviation, @Today, @MaxDate
    FROM dbo.STG_WEATHER source
    LEFT JOIN dbo.dim_location target 
        ON source.city = target.city 
       AND target.date_to = @MaxDate -- checking for current active rows for a city
    WHERE target.city IS NULL; -- if there are no active rows for a city then an insert happens 
END;
GO  

GRANT EXECUTE ON dbo.PROC_POPULATE_DIM_LOCATION to public;
GO -- granting execute to public, fastest way here, not good practice in general

---

CREATE PROCEDURE dbo.PROC_POPULATE_DIM_UNIT
AS 
 
BEGIN

INSERT INTO dbo.dim_unit (temperature_unit, precipitation_unit, humidity_unit)
VALUES ('Celsius', 'mm', '%');

INSERT INTO dbo.dim_unit (temperature_unit, precipitation_unit, humidity_unit)
VALUES ('Celsius', 'inch', '%');

INSERT INTO dbo.dim_unit (temperature_unit, precipitation_unit, humidity_unit)
VALUES ('Fahrenheit', 'mm', '%');

INSERT INTO dbo.dim_unit (temperature_unit, precipitation_unit, humidity_unit)
VALUES ('Fahrenheit', 'inch', '%');
  
END;
GO  

GRANT EXECUTE ON dbo.PROC_POPULATE_DIM_UNIT to public;
GO -- granting execute to public, fastest way here, not good practice in general

--- fact procedure

CREATE PROCEDURE dbo.PROC_FACT_WEATHER_FORECAST
AS 
 
BEGIN
    -- since this is a fact table and only the latest state is available no need for updates
    -- inserting new rows if there is a new measurement (based on date) for a city

    INSERT INTO dbo.FACT_WEATHER_FORECAST (
        date_key, location_key, unit_key, temperature_2m, 
        precipitation, relative_humidity_2m, precipitation_probability,
    utc_offset_seconds        
    )
    SELECT 
        d_date.date_key, loc.location_key, 
        unit.unit_key, 
        source.temperature_2m,
        source.precipitation, source.relative_humidity_2m, source.precipitation_probability,
        source.utc_offset_seconds
    FROM dbo.STG_WEATHER source
    join dbo.DIM_DATE d_date on CONVERT(INT,REPLACE(LEFT(source.time,10),'-',''))=d_date.date_key
    join dbo.DIM_LOCATION loc on source.city=loc.city and loc.date_to = DATEFROMPARTS(9999,12,31)
    join dbo.DIM_UNIT unit on 
            CASE 
            WHEN source.temperature_2m_unit LIKE '%C' THEN 'Celsius'
            WHEN source.temperature_2m_unit LIKE '%F' THEN 'Fahrenheit'
            ELSE source.temperature_2m_unit 
       END = unit.temperature_unit
   AND source.precipitation_unit = unit.precipitation_unit
   AND source.relative_humidity_2m_unit = unit.humidity_unit

   left join dbo.FACT_WEATHER_FORECAST target on d_date.date_key=target.date_key and loc.location_key=target.location_key -- we just want inserts to happen if a measurement doesn't exist for a city for a certain day, we ignore measurements with new units for the same city for the same day

   WHERE target.date_key is null 
END;
GO  

GRANT EXECUTE ON dbo.PROC_FACT_WEATHER_FORECAST to public;
GO -- granting execute to public, fastest way here, not good practice in general
