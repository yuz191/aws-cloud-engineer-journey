-- Run only after importing the supplied dump into a temporary training_data database.
-- The source has identifying fields beyond the 17 columns listed in the handbook.
-- Copy only the columns required by PropertyLite and the Week 4 exercises.
USE training_data;

CREATE TABLE sanitized_rets_property AS
SELECT
  CONCAT('R', 100000 + ROW_NUMBER() OVER (ORDER BY id)) AS L_ListingID,
  L_City,
  L_Keyword2,
  LM_Dec_3,
  LM_Int2_3,
  L_SystemPrice,
  L_Status
FROM rets_property;

ALTER TABLE sanitized_rets_property
  MODIFY L_ListingID VARCHAR(20) NOT NULL,
  ADD PRIMARY KEY (L_ListingID);

-- The raw table, including names, contact details, addresses, coordinates,
-- photos, remarks, original MLS IDs, and its original row IDs, is removed.
DROP TABLE rets_property;
RENAME TABLE sanitized_rets_property TO rets_property;
