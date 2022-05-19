

begin tran

-- Opgave 1

create table Station(
	stationsnummer char(8) not null primary key,
	postnummer char(4) not null
)

create table Klasse(
	klasse char(1) not null primary key,
	døgnpris decimal not null,
	kilometerpris decimal not null
)

create table Bil(
	registreringsnummer char(7) not null primary key,
	beskrivelse nvarchar(255) not null,
	klasse char(1) not null foreign key references Klasse(klasse),
	stationsnummer char(8) not null foreign key references Station(stationsnummer)
)

create table Skade(
	bil char(7) not null foreign key references Bil(registreringsnummer) on delete cascade, -- Clustered index er ikke på, da bil ikke er primary key, eftersom den ikke skal være unik.
	beskrivelse nvarchar(255) not null,
	grad int not null -- Bruges til at vurdere om bilen skal pensioneres, eller pøskrives en rabat. Jo højere en grad, jo vørre en skade, derved kan man summe alle graden af alle skader pø en bil
	-- Det kan diskuteres om der skal vøre en nullable reference til Kunden, sø det er muligt at fø en skadeshistorik pø en kunde nør de booker en bil. (Det vurderes at vøre uden for scope) (Nullable da skaden kan vøre forørsaget af andre en kunden)
)

create table Kunde(
	kundenummer int not null primary key identity (1000000, 1),
	navn nvarchar(255) not null,
	adresse nvarchar(255) not null,
	postnummer char(4) not null,
	email nvarchar(255) not null unique
)

create table Booking(
	bookingnummer int not null primary key identity (1,1),
	kundenummer int not null foreign key references Kunde(kundenummer),
	startdato datetime not null,
	døgn int not null default(1),
	forhandletPris decimal null,
	bil char(7) not null foreign key references Bil(registreringsnummer)
)

create table Afhentning( -- Denne tabel dækker både over afhentning og aflevering. Den er for at separere en booking fra afhentningen af bilen. Kilometer ved afhentning er ikke nødvendigvis det samme som kilometer ved booking. Den gør også logikken omkring ændring af en booking simplere, da man ikke skal ind og ændre i den for at søtte kilometer ved slut.
	bookingnummer int not null primary key,
	kilometerVedStart int not null,
	kilometerVedSlut int null,
	foreign key (bookingnummer) references Booking(bookingnummer) on delete cascade,
)

go

insert into Station values ('82401748', '8240')
insert into Station values ('80006357', '8000')
insert into Station values ('82106284', '8210')

insert into Klasse values ('A', 1000, 30)
insert into Klasse values ('B', 1500, 40)
insert into Klasse values ('C', 2000, 50)
insert into Klasse values ('D', 3000, 70)
insert into Klasse values ('E', 5000, 100)

insert into Bil values ('XC53265', 'Panda, Fiat', 'B', '82401748')
insert into Bil values ('QH68543', 'M3, BMW', 'D', '82401748')
insert into Bil values ('NH89432', 'Punto, Fiat', 'A', '80006357')
insert into Bil values ('IO35649', 'A-klasse, Mercedes-Benz', 'C', '80006357')
insert into Bil values ('PA52454', 'E-klasse, Mercedes-Benz', 'E', '80006357')
insert into Bil values ('GG12489', 'Polo, VW', 'B', '80006357')
insert into Bil values ('TR43518', 'Polo, VW', 'B', '82106284')
insert into Bil values ('CL42791', 'Corolla, Toyota', 'A', '82106284')

insert into Skade values ('XC53265', 'Rids pø dør, førerside', 20)
insert into Skade values ('XC53265', 'Bule i køfanger foran', 100)
insert into Skade values ('IO35649', 'Misfarvning pø bagsøde', 10)

insert into Kunde (navn, adresse, postnummer, email) values ('Birgitte Gregersen', 'Strandvejen 1', '8240', 'bgregs@gmail.com')
insert into Kunde (navn, adresse, postnummer, email) values ('Hans Christian Andersen', 'tulipanvej 8', '5000', 'hcandersen@wonderland.com')

insert into Booking (kundenummer, startdato, døgn, forhandletPris, bil) values (1000001, '2022/05/21 07:00', 3, null, 'GG12489')
insert into Afhentning values (1, 4245, 4320)
insert into Booking (kundenummer, startdato, døgn, forhandletPris, bil) values (1000001, '2022/06/15 09:00', 7, null, 'GG12489')
insert into Afhentning values (2, 424154, 428463)
insert into Booking (kundenummer, startdato, døgn, forhandletPris, bil) values (1000001, '2022/06/15 09:00', 7, null, 'TR43518')
insert into Afhentning values (3, 424154, 428463)
insert into Booking (kundenummer, startdato, døgn, forhandletPris, bil) values (1000001, '2022/07/25 09:00', 7, null, 'TR43518')
insert into Afhentning values (4, 424154, 428463)


go

-- Opgave 2

-- Booking starttidspunkt skal vøre inden for åbningstiderne
alter table Booking
add constraint erIndenForåbningstid check (datepart(hour, startdato) >= 6 and datepart(hour, startdato) < 20 and startdato > getdate())

go

drop trigger if exists bookingTrigger

go

-- En booking må ikke ændres eller slettes hvis startdato er inden for 5 dage
create trigger bookingTrigger
on Booking
instead of UPDATE, DELETE
as
	begin tran

	if (select count(*) from deleted b where datediff(day, getdate(), b.startdato) <= 5) > 0
	begin
		print('Error updating or deleting booking')
		rollback
	end
	else
	begin
		update Booking
		set	
			kundenummer = i.kundenummer,
			startdato = i.startdato,
			døgn = i.døgn,
			forhandletPris = i.forhandletPris,
			bil = i.bil
		from Booking b
		join inserted i on b.bookingnummer = i.bookingnummer
		
		delete from booking 
		where bookingnummer in (select bookingnummer from deleted)
		
		commit
	end

-- Opgave 4

go

drop index if exists ix_dato on Booking

go

create index ix_dato on Booking (bil, startdato, døgn)

go

drop procedure if exists sp_ledigeBiler

go

create procedure sp_ledigeBiler @station char(8), @klasse char(1), @startdato datetime, @døgn int
as
	select bil.registreringsnummer, bil.beskrivelse
	from Bil bil
	where 
		bil.klasse = @klasse and 
		bil.stationsnummer = @station and
		bil.registreringsnummer not in (select bil from Booking where booking.startdato <= dateadd(day, @døgn, @startdato) and dateadd(day, booking.døgn, booking.startdato) >= @startdato)
		

go

exec sp_ledigeBiler @station = '82106284', @klasse = 'B', @startdato = '2022/05/21 10:00', @døgn = 4

--(2 rows affected)
--Table 'Booking'. Scan count 1, logical reads 28, physical reads 0, page server reads 0, read-ahead reads 0, page server read-ahead reads 0, lob logical reads 0, lob physical reads 0, lob page server reads 0, lob read-ahead reads 0, lob page server read-ahead reads 0.
--Table 'Bil'. Scan count 1, logical reads 2, physical reads 0, page server reads 0, read-ahead reads 0, page server read-ahead reads 0, lob logical reads 0, lob physical reads 0, lob page server reads 0, lob read-ahead reads 0, lob page server read-ahead reads 0.
--
--(1 row affected)
--
--Completion time: 2022-05-19T16:06:37.0693582+02:00

--(2 rows affected)
--Table 'Booking'. Scan count 2, logical reads 4, physical reads 0, page server reads 0, read-ahead reads 0, page server read-ahead reads 0, lob logical reads 0, lob physical reads 0, lob page server reads 0, lob read-ahead reads 0, lob page server read-ahead reads 0.
--Table 'Bil'. Scan count 1, logical reads 2, physical reads 0, page server reads 0, read-ahead reads 0, page server read-ahead reads 0, lob logical reads 0, lob physical reads 0, lob page server reads 0, lob read-ahead reads 0, lob page server read-ahead reads 0.
--
--(1 row affected)
--
--Completion time: 2022-05-19T16:09:40.2998717+02:00




-- Opgave 5

-- Generate data for testing

declare @counter int
set @counter = 1 
while @counter <= 2000
begin
	
	insert into Kunde (navn, adresse, postnummer, email) values ('Birgitte Gregersen', 'Strandvejen 1', '8240', 'bgregs@gmail.com' + convert(nvarchar, @counter))
	declare @bil char(7)
	select @bil = registreringsnummer from Bil -- Få en jævn distribution af biler
				  order by registreringsnummer
				  offset @counter % 10 rows
				  fetch next 1 rows only

	if @counter % 10 = 0 
		insert into Booking (kundenummer, startdato, døgn, forhandletPris, bil) values (@@identity, dateadd(day, @counter, '2022/07/25 09:00'), 5, 4000, @bil)
	else
		insert into Booking (kundenummer, startdato, døgn, forhandletPris, bil) values (@@identity, dateadd(day, @counter, '2022/07/25 09:00'), 5, null, @bil)

	insert into Afhentning values (@@identity, 1000, 1200)

	set @counter += 1
end

set @counter = 0

go

declare @i int
set @i = 1 
while @i <= 200
begin
	
	declare @bil char(7)
	select @bil = registreringsnummer from Bil -- Få en jævn distribution af biler
				  order by registreringsnummer
				  offset @i % 10 rows
				  fetch next 1 rows only

	insert into Skade values (@bil, 'Bule', 10 * (@i % 30))

	set @i += 1
end

set @i = 1


go

drop index if exists ix_skader on Skade

go

create clustered index ix_skader on Skade(bil)

go

select s.beskrivelse 
from Skade s
join Bil b on s.bil = b.registreringsnummer
where b.registreringsnummer = 'GG12489'

--(20 rows affected)
--Table 'Skade'. Scan count 1, logical reads 3483, physical reads 0, page server reads 0, read-ahead reads 0, page server read-ahead reads 0, lob logical reads 0, lob physical reads 0, lob page server reads 0, lob read-ahead reads 0, lob page server read-ahead reads 0.
--Table 'Bil'. Scan count 0, logical reads 2, physical reads 0, page server reads 0, read-ahead reads 0, page server read-ahead reads 0, lob logical reads 0, lob physical reads 0, lob page server reads 0, lob read-ahead reads 0, lob page server read-ahead reads 0.
--
--(1 row affected)


--(20 rows affected)
--Table 'Skade'. Scan count 1, logical reads 2, physical reads 0, page server reads 0, read-ahead reads 0, page server read-ahead reads 0, lob logical reads 0, lob physical reads 0, lob page server reads 0, lob read-ahead reads 0, lob page server read-ahead reads 0.
--Table 'Bil'. Scan count 0, logical reads 2, physical reads 0, page server reads 0, read-ahead reads 0, page server read-ahead reads 0, lob logical reads 0, lob physical reads 0, lob page server reads 0, lob read-ahead reads 0, lob page server read-ahead reads 0.
--
--(1 row affected)


set statistics io off

-- Scenarie: Aflevering af bil
-- Bruger afleverer bilen ved station
-- Systemet registrer skader hvis opstået
-- Systemet udregner pris
-- Brugeren betaler (uden for scope)

declare @bookingnummer int = 4275
declare @station int = 43251748

update Afhentning
set kilometerVedSlut = kilometerVedStart + 150
where bookingnummer = @bookingnummer

update Bil
set bil.stationsnummer = @station
from Bil bil
join Booking booking on booking.bil = bil.registreringsnummer
where booking.bookingnummer = @bookingnummer

-- Skader

select 
	case when b.forhandletPris is not null then b.forhandletPris 
		else ((b.døgn + 1) * k.døgnpris) + (k.kilometerpris * 
			case 
				when a.kilometerVedSlut - a.kilometerVedStart - (50 * b.døgn) < 0 then 0 
				else (a.kilometerVedSlut - a.kilometerVedStart - (50 * b.døgn))
			end
	) end
from Booking b
join Bil bil on b.bil = bil.registreringsnummer
join Klasse k on bil.klasse = k.klasse
join Afhentning a on a.bookingnummer = b.bookingnummer
where b.bookingnummer = @bookingnummer

commit tran
