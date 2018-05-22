USE [BLU]
GO

/****** Object:  View [dbo].[MagentoPromDateExport14]    Script Date: 5/22/2018 2:03:22 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO






CREATE View [dbo].[MagentoPromDateExport14] 

as 

select 'sku'as sku,'bd_backorder_date' as bd_backorder_date

union all

select rtrim(a.ITEMNMBR),
CASE 
when b.[Promise Date] is null then ''
when b.[Promise Date]='01/01/1900' then ''
else  ISNULL(rtrim(CONVERT(varchar(10), b.[Promise Date]+14, 101)),'')
end as PromiseDate
from IV00101 a 
left join  EXTIVCARD b
on a.Itemnmbr=b.[Item Number]
where a.ITMGEDSC='WEB'
and a.INACTIVE=0
and a.uscatvls_2 = 'yes' -- Added April 2018 with Promise Date Query updates
and a.ITEMNMBR not in (select ITEMNMBR from BM00101 where Bill_Status = 1) -- Added (possibly temporary) to just monitor BOM dates before pushing to website

GO

