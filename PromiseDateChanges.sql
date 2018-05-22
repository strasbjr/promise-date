USE [IT]
GO

/****** Object:  StoredProcedure [dbo].[PromiseDateCalculation]    Script Date: 5/22/2018 2:23:52 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO



CREATE Procedure [dbo].[PromiseDateCalculation]
as

SET ANSI_WARNINGS  OFF

-- run this to populate data for QC
exec BLU..DSXOpenReceipts

-- clear working tables
delete from BLU..IVPromiseDateWork
delete from IT..PromiseDateBefore
delete from IT..PromiseDateAfter


--Declare Variable for Insert\Update of Extender Tables

Declare @FieldID_PromiseDate int,
        @FieldID_PromiseDateFromPO int,
		@results int,
		@tableHTML  NVARCHAR(MAX)

select @FieldID_PromiseDate=Field_ID from BLU..EXT20010 where FIELDNAM = 'Promise Date'

select @FieldID_PromiseDateFromPO=Field_ID from BLU..EXT20010 where FIELDNAM='Promise Date From PO'

-- Populate a "before" look at promise dates

insert into IT..PromiseDateBefore
select	Extender_Key_Values_1,
		Extender_Record_ID,
		NULL,
		NULL
from	BLU..EXT01100
where	Extender_Window_ID = 'INVENTORY CARD'

update	IT..PromiseDateBefore
set		promiseDate = date1
from	IT..PromiseDateBefore b
join	BLU..ext01102 e on b.extender_record_id = e.Extender_Record_ID and e.Field_ID = @FieldID_PromiseDate

update	IT..PromiseDateBefore
set		promiseDateFromPO = total
from	IT..PromiseDateBefore b
join	BLU..ext01103 e on b.extender_record_id = e.Extender_Record_ID and e.Field_ID = @FieldID_PromiseDateFromPO

--Delete Previous Promise Date Data for available items
delete BLU..EXT01103 
from BLU..EXT01103 e1
join BLU..EXT01100 e2 on e1.Extender_Record_ID = e2.Extender_Record_ID 
join BLU..IV00101 i on e2.Extender_Key_Values_1 = i.ITEMNMBR
JOIN BLU..iv00102 LOC ON I.itemnmbr = LOC.itemnmbr 
where Field_ID = @FieldID_PromiseDateFromPO
and	Extender_Window_ID='INVENTORY CARD'
and  (( LOC.qtyonhnd - LOC.atyalloc - loc.QTYBKORD > 0 ) or ITEMTYPE = 3) -- also remove kits (all will show 0 available per the qty columns)
AND LOC.locncode IN ( 'BDMN' ) 
				
delete BLU..EXT01102 
from BLU..EXT01102 e3
join BLU..EXT01100 e4 on e3.Extender_Record_ID = e4.Extender_Record_ID
join BLU..IV00101 i on e4.Extender_Key_Values_1 = i.ITEMNMBR
JOIN BLU..iv00102 LOC ON I.itemnmbr = LOC.itemnmbr 
where Field_ID = @FieldID_PromiseDate
and	Extender_Window_ID='INVENTORY CARD'
and  (( LOC.qtyonhnd - LOC.atyalloc - loc.QTYBKORD > 0 ) or ITEMTYPE = 3) -- also remove kits (all will show 0 available per the qty columns)
AND LOC.locncode IN ( 'BDMN' )  

--Declare Table Variable for PO data

DECLARE @POPDATA TABLE 
  ( 
     ponumber  CHAR(20), 
     polnesta  SMALLINT, 
     ord       INT, 
     qtyorder  NUMERIC, 
     prmdate   DATETIME, 
     itemnmber CHAR (31), 
     locncode  CHAR (11) 
  ) 

INSERT INTO @POPDATA 
SELECT POP.ponumber, 
       POP.polnesta, 
       POP.ord, 
       POP.qtyorder, 
       POP.prmdate, 
       POP.itemnmbr, 
       POP.locncode 
FROM   BLU..pop10110 POP -- PO LINE WORK TABLE
       LEFT JOIN BLU..pop10500 REC -- POP RECEIPT TABLE
              ON ( POP.ponumber = REC.ponumber 
                   AND POP.ord = REC.polnenum ) 
       LEFT JOIN BLU..iv10200 CL -- INVENTORY PURCHASE RECEIPT TABLE - CONFIRM GOODS ARE STILL IN RECEIPT LOCATION
              ON ( REC.itemnmbr = CL.itemnmbr 
                   AND REC.poprctnm = CL.rcptnmbr 
                   AND REC.rctseqnm = CL.rctseqnm ) 
WHERE  ( ( POP.polnesta IN ( 2, 3 ) 
                           AND POP.locncode IN ( 'BDMN', 'QC', 'OCEAN' ) ) 
                           OR ( POP.polnesta IN ( 4, 5 ) --  THIS INCLUDES "5-CLOSED" OCEAN PO LINES THAT MAY STILL BE IN THE OCEAN LOCATION
                           AND POP.locncode IN ( 'OCEAN' ) 
                           AND CL.rcptsold = 0 ) ) 
       AND POP.prmdate >= Getdate() 
       AND POP.ponumber <> 'DUMMYORDER' 
union all
SELECT POP.ponumber, 
       POP.polnesta, 
       POP.ord, 
       POP.qtyorder, 
       POP.prmdate, 
       POP.itemnmbr, 
       POP.locncode
FROM   BLU..pop30110 POP -- PO LINE WORK TABLE
       LEFT JOIN BLU..pop10500 REC -- POP RECEIPT TABLE
              ON ( POP.ponumber = REC.ponumber 
                   AND POP.ord = REC.polnenum ) 
       LEFT JOIN BLU..iv10200 CL -- INVENTORY PURCHASE RECEIPT TABLE - CONFIRM GOODS ARE STILL IN RECEIPT LOCATION
              ON ( REC.itemnmbr = CL.itemnmbr 
                   AND REC.poprctnm = CL.rcptnmbr 
                   AND REC.rctseqnm = CL.rctseqnm ) 
WHERE  ( ( POP.polnesta IN ( 2, 3 ) 
                           AND POP.locncode IN ( 'BDMN', 'QC', 'OCEAN' ) ) 
                           OR ( POP.polnesta IN ( 4, 5 ) --  THIS INCLUDES "5-CLOSED" OCEAN PO LINES THAT MAY STILL BE IN THE OCEAN LOCATION
                           AND POP.locncode IN ( 'OCEAN' ) 
                           AND CL.rcptsold = 0 ) ) 
       AND POP.prmdate >= Getdate() 
       AND POP.ponumber <> 'DUMMYORDER'

-- Insert items in QC. This table is calculated during the execution of the sproc DSXOpenReceipts (done at the beginning of this query)
 INSERT INTO @POPDATA 
 (itemnmber,ponumber,qtyorder,prmdate)
 select	itemnumber,
		ponumber,
		quantity,
		promisedate
 from	IT..QCPromiseDate

--Declare Table Variable for Item Data

DECLARE @ITEMDATA TABLE 
  ( 
     itemnmbr CHAR(31), 
     locncode CHAR (11), 
     itemtype SMALLINT, 
     qtybkord NUMERIC (19, 5) 
  ) 

INSERT INTO @ITEMDATA 
SELECT INV.itemnmbr, 
       LOC.locncode, 
       INV.itemtype, 
       LOC.qtybkord 
FROM   BLU..iv00101 INV -- ITEM MASTER
       JOIN BLU..iv00102 LOC -- ITEM QUANTITY MASTER
         ON INV.itemnmbr = LOC.itemnmbr 
WHERE  ( LOC.qtyonhnd - LOC.atyalloc - loc.QTYBKORD <= 0 ) 
       AND LOC.locncode IN ( 'BDMN' ) 
       AND INV.itemtype = 1 
       AND INV.inactive = 0 
       AND INV.uscatvls_2 <> 'No' 
	   and INV.uscatvls_1 <> 'No'  -- Jer added
	   and INV.ITMGEDSC = 'WEB' -- Jer added
	   and INV.ITMCLSCD not in ('MATTRESSES','FIXTURES','SWATCH','CLAD') -- Jer added
	   and INV.ITEMNMBR not in (select ITEMNMBR from BLU..BM00101 where bill_status = 1) -- exclude BOM parents, these will be handled further down
	   and inv.USCATVLS_5 not in ('Fixtures','Service','Support','Swag')

--Populate Current State Promise Date Work table. Left Join to pull all backordered items, not just those on PO

INSERT INTO BLU..[IVPromiseDateWork]
           ([ITEMNMBR]
           ,[LOCNCODE]
           ,[ITEMTYPE]
           ,[QTYBKORD]
                ,[PONUMBER]
           ,[POLNESTA]
                ,[ORD]
                ,[QTYORDER]
                ,[PRMDATE])

SELECT ITEM.itemnmbr, 
       ITEM.locncode, 
       ITEM.itemtype, 
       ITEM.qtybkord, 
       POP3.ponumber, 
       POP3.polnesta, 
       POP3.ord, 
       POP3.qtyorder, 
       POP3.prmdate 
FROM   @ITEMDATA ITEM -- FILTERED ITEM DATA
       LEFT JOIN @POPDATA POP3 -- FILTERED POP/RECEIPT DATA
               ON ITEM.itemnmbr = POP3.itemnmber 
ORDER  BY ITEM.itemnmbr, 
          POP3.prmdate   

/***
These extender table inserts are done first to account for new items that are yet to have any promise dates.
This will allow the subsequent query to determine that lack of any previous promise date to determine how
to properly update it.

Similar statements will be run again on the data AFTER the Kit/BOM rows have been added to IVPromiseDateWork
***/

-- Insert any new records to the main Extender table EXT01100
Declare @ITEMNMBR1 char (31)
declare Get_Items1 cursor
for 
select [itemnmbr] from BLU..IVPromiseDateWork where [itemnmbr]  not in (select extender_key_values_1 from BLU..ext01100 where Extender_Window_ID='Inventory Card')
Open Get_Items1
Fetch Next from Get_Items1 into @ITEMNMBR1
WHILE @@FETCH_STATUS = 0
Begin
Begin Transaction
Declare @ExtenderRecID1 int
select @ExtenderRecID1 = max(Extender_Record_ID)+1 from BLU..EXT01100
insert into BLU..EXT01100 (Extender_Record_ID,Extender_Window_ID,Extender_Key_Values_1)
values (@ExtenderRecID1,'INVENTORY CARD',@ITEMNMBR1)
commit transaction
Fetch Next from Get_Items1 into @ITEMNMBR1
end
close Get_Items1
Deallocate Get_Items1

-- Insert any new records to the extender table that holds the promise date
insert into BLU..EXT01102(Extender_Record_ID,Field_ID)
select distinct Extender_Record_ID,@FieldID_PromiseDate
from BLU..EXT01100 b join BLU..IVPromiseDateWork c on b.Extender_Key_Values_1=c.ITEMNMBR
where b.Extender_Window_ID='INVENTORY CARD'
and b.Extender_Record_ID not in (select Extender_Record_ID from BLU..EXT01102 where Field_ID=@FieldID_PromiseDate)

-- Insert any new records to the extender table that holds the indicator regarding how the promise date was derived
insert into BLU..EXT01103(Extender_Record_ID,Field_ID)
select distinct Extender_Record_ID,@FieldID_PromiseDateFromPO   
from BLU..EXT01100 b join BLU..IVPromiseDateWork c on b.Extender_Key_Values_1=c.Itemnmbr 
where b.Extender_Window_ID='INVENTORY CARD'
and b.Extender_Record_ID not in (select Extender_Record_ID from BLU..EXT01103 where Field_ID=@FieldID_PromiseDateFromPO)

-- Update Promise Dates but not overwriting previously calculated dates
Update BLU..[IVPromiseDateWork] 
set PRMDATE=BLU.dbo.GETPROMISEDATE(b.Itemnmbr,b.QtyBKord), 
	PRMDATECalc=case when 
			(
				BLU.dbo.GETPROMISEDATE(b.Itemnmbr,b.QtyBKord) is null  -- no PO promise date returned
				and
				(select total 
				from BLU..EXT01103 e1
				join BLU..EXT01100 e2 on e1.Extender_Record_ID = e2.Extender_Record_ID 
				where Field_ID = @FieldID_PromiseDateFromPO
				and	Extender_Window_ID='INVENTORY CARD'
				and Extender_Key_Values_1 = b.itemnmbr) = 1  -- current saved date is from a PO
			)
				or
			(
				(select total 
				from BLU..EXT01103 e1
				join BLU..EXT01100 e2 on e1.Extender_Record_ID = e2.Extender_Record_ID 
				where Field_ID = @FieldID_PromiseDateFromPO
				and	Extender_Window_ID='INVENTORY CARD'
				and Extender_Key_Values_1 = b.itemnmbr) in (0, NULL)  -- current saved date is not from a PO
				and
				(select date1 
				from BLU..EXT01102 e3
				join BLU..EXT01100 e4 on e3.Extender_Record_ID = e4.Extender_Record_ID
				where Field_ID = @FieldID_PromiseDate
				and	Extender_Window_ID='INVENTORY CARD'
				and Extender_Key_Values_1 = b.itemnmbr) in ('01/01/1900',NULL) -- current saved date is blank
			)
				or 
				BLU.dbo.GETPROMISEDATE(b.Itemnmbr,b.QtyBKord) is not null 
				then convert(varchar,isnull(BLU.dbo.GETPROMISEDATE(b.itemnmbr,b.QtyBKord),(GETDATE()+46+isnull(f.[Transit Days],0)+isnull(e.PLANNINGLEADTIME,0))),101)
				else convert(char(10),x.[Promise Date],101)
				end,
	PRMDATEFromPO=case when BLU.dbo.GETPROMISEDATE(b.Itemnmbr,b.QtyBKord) is null then 0 else 1 end
from BLU..IVPromiseDateWork b
left join BLU..IV00102 c on b.itemnmbr=c.itemnmbr and c.locncode='BDMN'
left join BLU..PM00200 d on c.PRIMVNDR=d.vendorid
left join BLU..IV00103 e on d.VENDORID=e.vendorid and e.ITEMNMBR=b.ITEMNMBR
left join BLU..EXTVENDCARD f on d.VENDORID=f.[Vendor ID]
join BLU..EXTIVCARD x on b.itemnmbr = x.[Item Number]

--Email Notification of Back Ordered Items without promise date
--Only send email at the first run (8:45am)
if (datename(hour,getdate()) = 8)
begin
	If exists (select ITEMNMBR from BLU..IVPromiseDateWork where BLU.dbo.GETPROMISEDATE(Itemnmbr,QtyBKord) is null)
	Begin
		SET @tableHTML =  
		N'<H1>Backordered Items without a PO Promise Date</H1>' +  
		N'<table border="1">' +  
		N'<tr><th>Item Number</th><th>Item Description</th>' +  
		N'<th>Quantity BackOrdered</th><th>Website ETA</th>' +  
		N'</tr>' +  
		CAST ( ( SELECT distinct td = w.ITEMNMBR,       '',  
						td = ITEMDESC, '',
		   td = isnull(QTYBKORD,0), '',
		   td = CASE 
				when w.PRMDATECalc is null then ''
				when w.PRMDATECalc='01/01/1900' then ''
				else  ISNULL(rtrim(CONVERT(varchar(10), w.PRMDATECalc+14, 101)),'')
				end
		from BLU.dbo.IVPromiseDateWork w 
		join BLU.dbo.iv00101 i on w.itemnmbr = i.itemnmbr
		where BLU.dbo.GETPROMISEDATE(w.Itemnmbr,QtyBKord) is null
		and	i.itemdesc not like 'DNR%'
		and w.itemnmbr in (select ITEMNMBR from BLU.dbo.POP30310 UNION select ITEMNMBR from BLU.dbo.POP10310)
		FOR XML PATH('tr'), TYPE   
		) AS NVARCHAR(MAX) ) +  
		N'</table>' ; 
	
		if (@@SERVERNAME = 'BLUDOT-SQL1')
		begin
			EXEC msdb.dbo.sp_send_dbmail
				@profile_name = 'Administrator',
				@recipients = 'inventoryplanner@BluDot.com',
				@subject = 'Backordered Items without a PO Promise Date',
				@body = @tableHTML,  
				@body_format = 'HTML' ;
		end
		else
		begin
			EXEC msdb.dbo.sp_send_dbmail
				@profile_name = 'Administrator',
				@recipients = 'jstrasburg@BluDot.com',
				@subject = '**DEV** Backordered Items without a PO Promise Date',
				@body = @tableHTML,  
				@body_format = 'HTML' ;
		end	
	End
end
-- Monday morning report 
if ((datename(hour,getdate()) = 8) and (datename(weekday,getdate()) = 'Monday')) 
begin
	If exists (select ITEMNMBR from BLU..IVPromiseDateWork where BLU.dbo.GETPROMISEDATE(Itemnmbr,QtyBKord) is null)
	Begin
		SET @tableHTML =  
		N'<H1>BO Items without a PO Promise Date (Never Been Received)</H1>' +  
		N'<table border="1">' +  
		N'<tr><th>Item Number</th><th>Item Description</th>' +  
		N'<th>Quantity BackOrdered</th><th>Website ETA</th>' +  
		N'</tr>' +  
		CAST ( ( SELECT distinct td = w.ITEMNMBR,       '',  
						td = ITEMDESC, '',
		   td = isnull(QTYBKORD,0), '',
		   td = CASE 
				when w.PRMDATECalc is null then ''
				when w.PRMDATECalc='01/01/1900' then ''
				else  ISNULL(rtrim(CONVERT(varchar(10), w.PRMDATECalc+14, 101)),'')
				end
		from BLU.dbo.IVPromiseDateWork w 
		join BLU.dbo.iv00101 i on w.itemnmbr = i.itemnmbr
		where BLU.dbo.GETPROMISEDATE(w.Itemnmbr,QtyBKord) is null
		and	i.itemdesc not like 'DNR%'
		and w.itemnmbr not in (select ITEMNMBR from BLU.dbo.POP30310 UNION select ITEMNMBR from BLU.dbo.POP10310)
		FOR XML PATH('tr'), TYPE   
		) AS NVARCHAR(MAX) ) +  
		N'</table>' ; 

		if (@@SERVERNAME = 'BLUDOT-SQL1')
		begin
			EXEC msdb.dbo.sp_send_dbmail
				@profile_name = 'Administrator',
				@recipients = 'inventoryplanner@BluDot.com',
				@subject = 'BO Items without a PO Promise Date (Never Been Received)',
				@body = @tableHTML,  
				@body_format = 'HTML' ;
		end
		else
		begin
			EXEC msdb.dbo.sp_send_dbmail
				@profile_name = 'Administrator',
				@recipients = 'jstrasburg@BluDot.com',
				@subject = '**DEV** BO Items without a PO Promise Date (Never Been Received)',
				@body = @tableHTML,  
				@body_format = 'HTML' ;
		end
	End
end

--Remove prior Kit/BOM Promise Date records
Delete from BLU..IVKitPromiseDateWork
Delete from BLU..IVBOMPromiseDateWork

-- Build up the work table to handle kit components (to ultimately get a date for the parent)
Insert into BLU..IVKitPromiseDateWork
(ITEMNMBR,LOCNCODE,ITEMTYPE,QTYBKORD,CMPTITNM,PRMDATE,PRMDATECalc,PRMDATEFromPO)
select distinct a.ITEMNMBR,b.LOCNCODE,'3',b.QTYBKORD,a.CMPTITNM,c.PRMDATE,c.PRMDATECalc,c.PRMDateFromPO
from BLU..IV00104 a 
join BLU..IV00102 b
on a.ITEMNMBR=b.ITEMNMBR
join BLU..IVPromiseDateWork c
on a.CMPTITNM=c.ITEMNMBR
where b.locncode='BDMN' 
order by a.itemnmbr

-- Build up the work table to handle BOM components (to ultimately get a date for the parent)
-- Only include BOM components that don't have available stock
Insert into BLU..IVBOMPromiseDateWork
(ITEMNMBR,LOCNCODE,ITEMTYPE,QTYBKORD,CMPTITNM,PRMDATE,PRMDATECalc,PRMDATEFromPO)
select distinct a.ITEMNMBR,b.LOCNCODE,'1',b.QTYBKORD,a.CMPTITNM,c.PRMDATE,c.PRMDATECalc,c.PRMDateFromPO
from BLU..BM00111 a 
join BLU..IV00102 b
on a.ITEMNMBR=b.ITEMNMBR
join BLU..IVPromiseDateWork c
on a.CMPTITNM=c.ITEMNMBR
where b.locncode='BDMN' 
and ( b.qtyonhnd - b.atyalloc - b.QTYBKORD <= 0 )
and Bill_Status = 1 
order by a.itemnmbr

-- Until it is decided how to handle BOMs, suppress this email
-- IF THIS IS UNCOMMENTED, MAKE SURE THE CALCULATED PROMISE IS ADDED TO THE RESULTS (SEE OTHER EMAILS ABOVE)

----Send Email if Back Ordered BOM Item is not On Order
--If exists (select ITEMNMBR from BLU.dbo.IVBOMPromiseDateWork where CMPTITNM in (select ITEMNMBR from BLU..IVPromiseDateWork where BLU.dbo.GETPROMISEDATE(Itemnmbr,QtyBKord) is null))
--Begin
--EXEC msdb.dbo.sp_send_dbmail
--    @profile_name = 'Administrator',
--    @recipients = 'jstrasburg@BluDot.com', --;thol@columbusglobal.com ',
--    @query = 'select distinct w.ITEMNMBR as BOMItemNumber,
--			ITEMDESC as Description,
--			QTYBKORD as QuantityBackOrdered,
--			CMPTITNM as ComponentItem
--			from BLU.dbo.IVBOMPromiseDateWork w 
--			join BLU.dbo.IV00101 i on w.itemnmbr = i.itemnmbr
--			where CMPTITNM in (select ITEMNMBR from BLU.dbo.IVPromiseDateWork where BLU.dbo.GETPROMISEDATE(Itemnmbr,QtyBKord) is null)
--			and	i.itemdesc not like "DNR%"' ,
--    @subject = 'BackOrdered BOMs without a PO Promise Date',
--    @attach_query_result_as_file = 1 ;
--End

-- In theory, this should not do any update as it would be updating a level 1 kit item which would not be in that table at this point.
Update BLU..IVPromiseDateWork
set PRMDATE=b.PRMDATE,PRMDATECALC=b.PRMDATECALC,PRMDATEFromPO=b.PRMDateFromPO
from BLU..IVPromiseDateWork a
join (select itemnmbr,max(PRMDATE) as PRMDATE,max(PRMDATECALC) as PRMDATECALC,case when max(PRMDATE)>=max(PRMDATECALC) then 1 else 0 end as PRMDateFromPO from BLU..IVKitPromiseDateWork group by Itemnmbr) b
on a.ITEMNMBR=b.ITEMNMBR

-- In theory, this should not do any update as it would be updating a level 1 BOM item which would not be in that table at this point.
Update BLU..IVPromiseDateWork
set PRMDATE=b.PRMDATE,PRMDATECALC=b.PRMDATECALC,PRMDATEFromPO=b.PRMDateFromPO
from BLU..IVPromiseDateWork a
join (select itemnmbr,max(PRMDATE) as PRMDATE,max(PRMDATECALC) as PRMDATECALC,case when max(PRMDATE)>=max(PRMDATECALC) then 1 else 0 end as PRMDateFromPO from BLU..IVBOMPromiseDateWork group by Itemnmbr) b
on a.ITEMNMBR=b.ITEMNMBR

-- Insert to the main working table the Kit level 1's with the max promise dates from their components
Insert into BLU..IVPromiseDateWork ([ITEMNMBR],[LOCNCODE],[PRMDATE],PRMDATECalc,PRMDATEFromPO)
Select itemnmbr,'BDMN',max(PRMDATE),max(PRMDATECALC),case when max(PRMDATE)>=max(PRMDATECALC) then 1 else 0 end
from BLU..IVKitPromiseDateWork where itemnmbr not in (select itemnmbr from BLU..IVPromiseDateWork) 
group by itemnmbr

-- Insert to the main working table the BOM level 1's with the max promise dates from their components
Insert into BLU..IVPromiseDateWork ([ITEMNMBR],[LOCNCODE],[PRMDATE],PRMDATECalc,PRMDATEFromPO)
Select itemnmbr,'BDMN',max(PRMDATE),max(PRMDATECALC),case when max(PRMDATE)>=max(PRMDATECALC) then 1 else 0 end
from BLU..IVBOMPromiseDateWork where itemnmbr not in (select itemnmbr from BLU..IVPromiseDateWork) 
group by itemnmbr

--Write to extender tables

-- A similar cursor was run above, however this needs to be done now to account
-- for Kit/BOM parents that have been added to IVPromiseDateWork since then.
Declare @ITEMNMBR char (31)
declare Get_Items cursor
for 
select [itemnmbr] from BLU..IVPromiseDateWork where [itemnmbr]  not in (select extender_key_values_1 from BLU..ext01100 where Extender_Window_ID='Inventory Card')
Open Get_Items
Fetch Next from Get_Items into @ITEMNMBR
WHILE @@FETCH_STATUS = 0
Begin
Begin Transaction
Declare @ExtenderRecID int
select @ExtenderRecID = max(Extender_Record_ID)+1 from BLU..EXT01100
insert into BLU..EXT01100 (Extender_Record_ID,Extender_Window_ID,Extender_Key_Values_1)
values (@ExtenderRecID,'INVENTORY CARD',@ITEMNMBR)
commit transaction
Fetch Next from Get_Items into @ITEMNMBR
end
close Get_Items
Deallocate Get_Items

-- Insert any new records to the extender table that holds the promise date; now catching new Kit/BOM parents as well
insert into BLU..EXT01102(Extender_Record_ID,Field_ID)
select distinct Extender_Record_ID,@FieldID_PromiseDate
from BLU..EXT01100 b join BLU..IVPromiseDateWork c on b.Extender_Key_Values_1=c.ITEMNMBR
where b.Extender_Window_ID='INVENTORY CARD'
and b.Extender_Record_ID not in (select Extender_Record_ID from BLU..EXT01102 where Field_ID=@FieldID_PromiseDate)
and c.PRMDATECalc is not null

-- Update the extender table with the promise date.  The PRMDATECalc field is used because it will always have either the promise date
-- from the PO or the calculated promise date
Update BLU..EXT01102
set Date1=c.PRMDATECalc
from BLU..EXT01102 a join BLU..EXT01100 B on a.Extender_Record_ID=b.Extender_Record_ID
join BLU..IVPromiseDateWork c on b.Extender_Key_Values_1=c.[ITEMNMBR]
where c.PRMDATECalc is not null and a.Field_ID=@FieldID_PromiseDate

-- Insert any new records to the extender table that holds the indicator regarding how the promise date was derived; now catching new Kit/BOM parents as well
insert into BLU..EXT01103(Extender_Record_ID,Field_ID)
select distinct Extender_Record_ID,@FieldID_PromiseDateFromPO   
from BLU..EXT01100 b join BLU..IVPromiseDateWork c on b.Extender_Key_Values_1=c.Itemnmbr 
where b.Extender_Window_ID='INVENTORY CARD'
and b.Extender_Record_ID not in (select Extender_Record_ID from BLU..EXT01103 where Field_ID= @FieldID_PromiseDateFromPO)
and c.PRMDATECalc is not null

-- Update the promise date indicator
Update BLU..EXT01103
set Total=
       case 
       when c.PRMDATEFromPO=1 then 1 
       else 0 end
from BLU..EXT01103 a join BLU..EXT01100 B on a.Extender_Record_ID=b.Extender_Record_ID
join BLU..IVPromiseDateWork c on b.Extender_Key_Values_1=c.[Itemnmbr]
where c.PRMDATECalc is not null and a.Field_ID=@FieldID_PromiseDateFromPO

--Send Email if Back Ordered Kit Item is not On Order
--Only send email at the first run (8:45am)
if (datename(hour,getdate()) = 8)
begin
	If exists (select ITEMNMBR from BLU.dbo.IVKitPromiseDateWork where CMPTITNM in (select ITEMNMBR from BLU..IVPromiseDateWork where BLU.dbo.GETPROMISEDATE(Itemnmbr,QtyBKord) is null))
	Begin
		SET @tableHTML =  
		N'<H1>BO Kits with no PO Promise Date</H1>' +  
		N'<table border="1">' +  
		N'<tr><th>Item Number</th><th>Item Description</th>' +  
		N'<th>Quantity BackOrdered</th><th>Component Item</th><th>Website ETA</th>' +  
		N'</tr>' +  
		CAST ( ( SELECT distinct td = w.ITEMNMBR,       '',  
						td = ITEMDESC, '',
		   td = QTYBKORD, '',
		   td = CMPTITNM, '',
		   td = m.bd_backorder_date
		from BLU.dbo.IVKitPromiseDateWork w 
		join BLU.dbo.IV00101 i on w.itemnmbr = i.itemnmbr
		join BLU.dbo.MagentoPromDateExport14 m on w.ITEMNMBR = m.sku
		where CMPTITNM in (select ITEMNMBR from BLU.dbo.IVPromiseDateWork where BLU.dbo.GETPROMISEDATE(Itemnmbr,QtyBKord) is null)
		and	i.itemdesc not like 'DNR%'
		FOR XML PATH('tr'), TYPE   
		) AS NVARCHAR(MAX) ) +  
		N'</table>' ; 

		if (@@SERVERNAME = 'BLUDOT-SQL1')
		begin
			EXEC msdb.dbo.sp_send_dbmail
			@profile_name = 'Administrator',
			@recipients = 'inventoryplanner@BluDot.com',
			@subject = 'Backordered Kits without a PO Promise Date',
			@body = @tableHTML,  
			@body_format = 'HTML' ;
		end
		else
		begin
			EXEC msdb.dbo.sp_send_dbmail
			@profile_name = 'Administrator',
			@recipients = 'jstrasburg@BluDot.com',
			@subject = '**DEV** Backordered Kits without a PO Promise Date',
			@body = @tableHTML,  
			@body_format = 'HTML' ;
		end
	End
end

-- Populate an "after" look at promise dates

insert into IT..PromiseDateAfter
select	Extender_Key_Values_1,
		Extender_Record_ID,
		NULL,
		NULL
from	BLU..EXT01100
where	Extender_Window_ID = 'INVENTORY CARD'

update	IT..PromiseDateAfter
set		promiseDate = date1
from	IT..PromiseDateAfter b
join	BLU..ext01102 e on b.extender_record_id = e.Extender_Record_ID and e.Field_ID = @FieldID_PromiseDate

update	IT..PromiseDateAfter
set		promiseDateFromPO = total
from	IT..PromiseDateAfter b
join	BLU..ext01103 e on b.extender_record_id = e.Extender_Record_ID and e.Field_ID = @FieldID_PromiseDateFromPO

-- This stops items that came back in stock from being added to tracking
delete from IT..PromiseDateAfter
where isnull(promiseDate,'01/01/1900') = '01/01/1900' 

-- Track changes
insert into IT..PromiseDateTracking
select	a.itemNumber,
		a.promiseDate,
		a.promiseDateFromPO,
		getdate(),
		suser_name()
from	IT..PromiseDateBefore b
join	IT..PromiseDateAfter a on b.itemNumber = a.itemnumber
where	(isnull(b.promiseDate,'01/01/1900') != isnull(a.promiseDate,'01/01/1900'))

select	@results = @@rowcount

-- Items not in EXT01100 at beginning of process but inserted during
insert into IT..PromiseDateTracking
select	itemNumber,
		promiseDate,
		promiseDateFromPO,
		getdate(),
		suser_name()
from	IT..PromiseDateAfter
where	itemNumber not in (select itemnumber from IT..PromiseDateBefore)

select	@results = @results + @@rowcount

-- Items not in IT..PromiseDateAfter but were in IT..PromiseDateBefore
if exists (select 1 from IT..PromiseDateBefore 
		   where	isnull(promiseDate,'01/01/1900') != '01/01/1900' 
		   and		itemNumber not in (select itemNumber from IT..PromiseDateAfter))
begin
	select @results = @results + 1
end

-- Email ETA changes
If (@results > 0)
Begin
	SET @tableHTML =  
		N'<H1>Website ETA Date Changes</H1>' +  
		N'<table border="1">' +  
		N'<tr><th>Item Number</th><th>Item Description</th>' +  
		N'<th>ETA Before</th><th>Date Origin Before</th><th>ETA Now</th>' +  
		N'<th>Date Origin Now</th><th>Qty Backordered</th></tr>' +  
		CAST ( ( SELECT td = ItemNumber,       '',  
						td = Description, '',
		   td = PromDateBefore, '',
		   td =  DateOriginBefore, '',
		   td =  PromDateNow, '',
		   td = DateOriginNow, '',
		   td = QtyBackordered
	from IT..PromiseDateChanges  
	FOR XML PATH('tr'), TYPE   
		) AS NVARCHAR(MAX) ) +  
		N'</table>' ; 

	if (@@SERVERNAME = 'BLUDOT-SQL1')
	begin
		EXEC msdb.dbo.sp_send_dbmail
			@profile_name = 'Administrator',
			@recipients = 'service@bludot.com',
			@subject = 'Website ETA Date Changes',
			@body = @tableHTML,  
			@body_format = 'HTML' ;
	end
	else
	begin
		EXEC msdb.dbo.sp_send_dbmail
			@profile_name = 'Administrator',
			@recipients = 'jstrasburg@BluDot.com',
			@subject = '**DEV** Website ETA Date Changes',
			@body = @tableHTML,  
			@body_format = 'HTML' ;
	end  
End

SET ANSI_WARNINGS  ON
GO

