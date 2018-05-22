USE [BLU]
GO

/****** Object:  StoredProcedure [dbo].[DSXOpenReceipts]    Script Date: 5/22/2018 2:21:50 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO




CREATE Procedure [dbo].[DSXOpenReceipts]
as

/*
	Note that Kyle M created a very similar proc called OTB_DSXOpenReceipts in the IT database 
	that should be evaluated when changes are made to this procedure.

	12-29-2017		Jeremy Strasburg - Added a UNION to select from history tables as well.
	04-18-2018		Jeremy Strasburg - Added an insert to a new table (IT..QCPromiseDate)
					and this proc is now called from the query in the Calculate Promise Date
					logic in the SQL Agent Job PODataExport.
*/

declare @DSXPOData table
(itemname varchar(50),
division varchar(50),
customer varchar (50),
shipto varchar (50),
[type] varchar (50),
quantity numeric (19,5),
Comment varchar(50),
EffectiveDate datetime,
WorkOrderNumber varchar (50),
POPRCTNUM varchar (50),
PRMDATE datetime,
ReceiveDate datetime,
QTYInTransitOnHand numeric (19,5),
[Include] int)




insert into @DSXPOData
select a.ITEMNMBR as ItemName,'' as Division,'' as Customer,'BDMN' as ShipTo,'' as Type,
case
when b.LOCNCODE  is null then(a.QTYORDER-a.QTYCANCE-isnull(b.QTYSHPPD,0))
else b.QTYSHPPD
end as Quantity,
Case
when b.LOCNCODE is not null then b.LOCNCODE
else 'OPEN'
end as Comment,
A.PRMDATE as EffectiveDate,a.PONUMBER as WorkOrderNumber,
b.POPRCTNM,a.PRMDATE,b.DateReceived,c.QTYInTransitOnHand,0
from POP10100 POHDR with (nolock) join
 POP10110 a  with (nolock) 
 on POHDR.PONumber=a.PONumber
 join IV00101  i with (nolock) 
on a.Itemnmbr=i.itemnmbr
join Iv00102 iq with (nolock) 
on i.itemnmbr=iq.itemnmbr
join IV00108 ip with (nolock) 
on i.itemnmbr=ip.itemnmbr
left join vw_intransit_receipts b with (nolock) 
left join vw_intransit_onhand c 
on b.ITEMNMBR=c.item_num and b.LOCNCODE=c.item_loc
on a. PONUMBER=b.PONUMBER and a.ord=b.ord
--where a.POLNESTA in (1,2,3,4,5) and a.LOCNCODE in ('OCEAN','QC','VENDOR')
where (a.POLNESTA in (1,2,3,4,5) and a.LOCNCODE in ('OCEAN','QC','VENDOR') and b.LOCNCODE is not null or a.POLNESTA in (1,2,3,4) and a.LOCNCODE in ('OCEAN','QC','VENDOR') and b.LOCNCODE is null)
and I.itemtype in (1,3) and iq.locncode='BDMN' and IP.PRCLEVEL='Retail' and I.USCATVLS_1=''
and I.USCATVLS_2='YES'  and I.ITMGEDSC='WEB'
--and a.ITEMNMBR in ('SR1-COFTBL-WH','HK1-OTTOMN-CL') --and a.PONUMBER='PO0021317'--'HK1-OTTOMN-CL' --in ('SR1-COFTBL-WH','SR1-MEDTBL-WH') 
and A.PRMDATE>getdate()-180 and POHDR.POType<>2 and a.LOCNCODE <> 'OCEANSPJ'
UNION
select a.ITEMNMBR as ItemName,'' as Division,'' as Customer,'BDMN' as ShipTo,'' as Type,
case
when b.LOCNCODE  is null then(a.QTYORDER-a.QTYCANCE-isnull(b.QTYSHPPD,0))
else b.QTYSHPPD
end as Quantity,
Case
when b.LOCNCODE is not null then b.LOCNCODE
else 'OPEN'
end as Comment,
A.PRMDATE as EffectiveDate,a.PONUMBER as WorkOrderNumber,
b.POPRCTNM,a.PRMDATE,b.DateReceived,c.QTYInTransitOnHand,0
from POP30100 POHDR with (nolock) join
 POP30110 a  with (nolock) 
 on POHDR.PONumber=a.PONumber
 join IV00101  i with (nolock) 
on a.Itemnmbr=i.itemnmbr
join Iv00102 iq with (nolock) 
on i.itemnmbr=iq.itemnmbr
join IV00108 ip with (nolock) 
on i.itemnmbr=ip.itemnmbr
left join vw_intransit_receipts b with (nolock) 
left join vw_intransit_onhand c 
on b.ITEMNMBR=c.item_num and b.LOCNCODE=c.item_loc
on a. PONUMBER=b.PONUMBER and a.ord=b.ord
--where a.POLNESTA in (1,2,3,4,5) and a.LOCNCODE in ('OCEAN','QC','VENDOR')
where (a.POLNESTA in (1,2,3,4,5) and a.LOCNCODE in ('OCEAN','QC','VENDOR') and b.LOCNCODE is not null or a.POLNESTA in (1,2,3,4) and a.LOCNCODE in ('OCEAN','QC','VENDOR') and b.LOCNCODE is null)
and I.itemtype in (1,3) and iq.locncode='BDMN' and IP.PRCLEVEL='Retail' and I.USCATVLS_1=''
and I.USCATVLS_2='YES'  and I.ITMGEDSC='WEB'
--and a.ITEMNMBR in ('SR1-COFTBL-WH','HK1-OTTOMN-CL') --and a.PONUMBER='PO0021317'--'HK1-OTTOMN-CL' --in ('SR1-COFTBL-WH','SR1-MEDTBL-WH') 
and A.PRMDATE>getdate()-180 and POHDR.POType<>2 and a.LOCNCODE <> 'OCEANSPJ'
order by a.itemnmbr,b.DateReceived desc


DECLARE @itemname varchar(50),
@quantity numeric (19,5),
@Comment varchar(50),
@QTY NUMERIC(19,5),
@QtyinTransitHand numeric(19,5),
@QtyBalance numeric(19,5),
@tmpitemname varchar(50),
@tmpComment varchar(50),
@WorkOrderNumber varchar (50),
@DateRcvd datetime,
@IsUpdate smallint

DECLARE  QtyCursor CURSOR FOR 
select itemname,Comment,quantity,QTYInTransitOnHand,WorkOrderNumber,ReceiveDate from @DSXPOData
order by itemname,comment,ReceiveDate desc

OPEN QtyCursor

FETCH NEXT FROM QtyCursor
INTO @Itemname,@Comment,@quantity,@QtyinTransitHand,@WorkOrderNumber,@DateRcvd

while @@FETCH_STATUS=0
begin
	if @Itemname<> isnull(@tmpitemname,'') OR @Comment<>isnull(@tmpcomment,'')
	begin
		set @tmpitemname=@Itemname
		set @tmpComment=@Comment
		set @QtyBalance=@QtyinTransitHand
	end

	set @IsUpdate=0

	--print @QtyBalance --print @tmpComment print @tmpitemname
	if isnull(@DateRcvd,'1900-01-01')='1900-01-01'
	  set @QTY=@quantity
	else if @quantity>@QtyBalance
	begin
		set @QTY=@QtyBalance
		set @QtyBalance=0		  
	end
	else if @quantity<=@QtyBalance
	begin
		set @QtyBalance=@QtyBalance-@quantity
		set @QTY=0
		set @IsUpdate=1
	end

	
	--print @quantity print @QtyBalance print @QtyinTransitHand print @qty
	if(@QTY<>0 )
	update @DSXPOData set quantity =@QTY,Include=1 where itemname=@itemname and Comment=@Comment and WorkOrderNumber=@WorkOrderNumber
	
	if (@IsUpdate=1 )
	update @DSXPOData set Include=1 where itemname=@itemname and Comment=@Comment and WorkOrderNumber=@WorkOrderNumber

FETCH NEXT FROM QtyCursor
INTO @Itemname,@Comment,@quantity,@QtyinTransitHand,@WorkOrderNumber,@DateRcvd
end
close QtyCursor
Deallocate QtyCursor

select * from @DSXPOData
where Include=1
order by itemname,ReceiveDate desc

-- Clear and repopulate table used by Promise Date Query for Website ETAs
delete from IT..QCPromiseDate

insert into IT..QCPromiseDate
select	itemname,
		WorkOrderNumber,
		quantity,
		PRMDATE	 
from	@DSXPOData 
where	Comment = 'QC'
and		Include = 1

GO

