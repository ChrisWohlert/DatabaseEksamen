

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
	klasse char(1) not null foreign key references Klasse(klasse), -- Potentielt kunne klasse sammenkobles med mærke og model i stedet, men så vil det ikke være muligt at rykke en bil ned i klasse som det får skader eller har mange kilometer
	stationsnummer char(8) not null foreign key references Station(stationsnummer)
)

create table Skade(
	bil char(7) not null foreign key references Bil(registreringsnummer), -- Clustered index er ikke på, da bil ikke er primary key, eftersom den ikke skal være unik.
	beskrivelse nvarchar(255) not null,
	grad int not null -- Bruges til at vurdere om bilen skal pensioneres, eller påskrives en rabat. Jo højere en grad, jo værre en skade, derved kan man summe alle graden af alle skader på en bil
	-- Det kan diskuteres om der skal være en nullable reference til Kunden, så det er muligt at få en skadeshistorik på en kunde når de booker en bil. (Det vurderes at være uden for scope) (Nullable da skaden kan være forårsaget af andre en kunden)
)

create table Kunde(
	kundenummer int not null primary key identity (1000000, 1),
	navn nvarchar(255) not null,
	adresse nvarchar(255) not null,
	postnummer char(4) not null,
	email nvarchar(255) not null
)

create table Booking(
	bookingnummer int not null primary key identity (1,1),
	kundenummer int not null foreign key references Kunde(kundenummer),
	startdato datetime not null,
	døgn int not null default(1),
	forhandletPris decimal null,
	bil char(7) not null foreign key references Bil(registreringsnummer)
)

create table Afhentning( -- Denne tabel dækker både over afhentning og aflevering. Den er for at separere en booking fra afhentningen af bilen. Kilometer ved afhentning er ikke nødvendigvis det samme som kilometer ved booking. Den gør også logikken omkring ændring af en booking simplere, da man ikke skal ind og ændre i den for at sætte kilometer ved slut.
	bookingnummer int not null primary key,
	kilometerVedStart int not null,
	kilometerVedSlut int null,
	foreign key (bookingnummer) references Booking(bookingnummer)
)

go

insert into Station values ('43251748', '8240')
insert into Station values ('15546357', '8000')
insert into Station values ('83456284', '8210')

insert into Klasse values ('A', 1000, 30)
insert into Klasse values ('B', 1500, 40)
insert into Klasse values ('C', 2000, 50)
insert into Klasse values ('D', 3000, 70)
insert into Klasse values ('E', 5000, 100)

insert into Bil values ('XC53265', 'Panda, Fiat', 'B', '43251748')
insert into Bil values ('QH68543', 'M3, BMW', 'D', '43251748')
insert into Bil values ('NH89432', 'Punto, Fiat', 'A', '15546357')
insert into Bil values ('IO35649', 'A-klasse, Mercedes-Benz', 'C', '15546357')
insert into Bil values ('PA52454', 'E-klasse, Mercedes-Benz', 'E', '83456284')
insert into Bil values ('GG12489', 'Polo, VW', 'B', '83456284')
insert into Bil values ('TR43518', 'Polo, VW', 'B', '83456284')
insert into Bil values ('CL42791', 'Corolla, Toyota', 'A', '43251748')

insert into Skade values ('XC53265', 'Rids på dør, førerside', 20)
insert into Skade values ('XC53265', 'Bule i køfanger foran', 100)
insert into Skade values ('IO35649', 'Misfarvning på bagsæde', 10)

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

-- Booking starttidspunkt skal være inden for åbningstiderne
alter table Booking
add constraint erIndenForÅbningstid check (datepart(hour, startdato) >= 6 and datepart(hour, startdato) < 20 and startdato > getdate())

drop trigger if exists bookingTrigger

go

-- En booking må ikke ændres eller slettes hvis startdato er inden for 5 dage
create trigger bookingTrigger
on Booking
instead of UPDATE, DELETE
as
	if exists (select * from (select startdato from inserted union select startdato from deleted) b where datediff(day, getdate(), b.startdato) <= 5) 
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

drop procedure if exists sp_ledigeBiler

go

-- Denne vil også sagtens kunne laves med en subquery, hvor man siger "Find bookings der overlapper, tag deres bil, filtre alle biler som ikke overlapper"
create procedure sp_ledigeBiler @station char(8), @klasse char(1), @startdato datetime, @døgn int
as
	select bil.*
	from Bil bil
	left join Booking booking -- left join i stedet for inner join, da biler uden bookings selvfølgelig er ledige
		on booking.bil = bil.registreringsnummer and 
		not (booking.startdato >= dateadd(day, @døgn, @startdato) or dateadd(day, booking.døgn, booking.startdato) <= @startdato)
	where 
		bil.klasse = @klasse and 
		bil.stationsnummer = @station and
		booking.bil is null
		

go

exec sp_ledigeBiler @station = '83456284', @klasse = 'B', @startdato = '2022/05/21 10:00', @døgn = 4


commit tran