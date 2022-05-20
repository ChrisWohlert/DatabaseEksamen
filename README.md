> Udarbejdet af Chris Wohlert

# Eksamensopgave Database for Udviklere
## Biludlejning

### Opgave 1

Biludlejning har en række forskellige data som skal opbevares for at understøtte forretningen. Disse data skal opbevares med henblik på korrekthed og ydeevne. SQL er et schema baseret database system, som hjælper med at opretholde visse regler som den enkelte appliklation ellers skulle tage sig af.
Der er taget højde for følgende relationelle krav:
 - Der må ikke oprettes en bil som ikke tilhører en klasse
 - Der må ikke oprettes en bil som ikke tilhører en station
 - Der må ikke oprettes en skade på en bil der ikke er i systemet
 - Der må ikke oprettes en booking uden en kunde
 - Der må ikke oprettes en booking uden en bil

Udover er der en række data attribut krav, så som *En bil skal have en nummerplade og beskrivelse*. Hvert punkt af disse kan ses i bilag. SQL tilader andre sikkerheder, som gør at applikationer ikke skal håndterer integriteten af data. Alt efter hvilke behov man har, kan man vurdere hvordan data skal slettes. Hvis en bil bliver slettet i systemet, skal alle dens bookinger og skader så også slettes? Hvis ikke, skal de så forblive, uden man kan se hvilken bil de tilhørte, eller skal det bare ikke være muligt at slette en bil, uden først at slette bookinger?
Disse tre muligheder kan implementeres med henholdsvis *on delete cascade*, *on delete set null* og *throw constraint violation*. Hvis man gerne vil have bookings forbliver i systemet efter bilen er væk, er det nødvendigt at en booking kan fremgå uden en bil. En af de relationelle krav bliver derved slækket. Om man vil have alle bookings bliver slettet når man sletter en bil, eller om man tvinger applikationer til selv først at slette bookings inden de sletter bilen er et tradeoff. At lade databasen stå for det, fremhæver dens ansvar for dataintegritet, men øger risikoen for mistet data ved en fejl. Andre tiltag kan tages, som backup, for at minimere dette. I denne løsning er der ikke lavet cascade, da det er vurderet at være for forretningskritisk data. Det er stadig kun mennesker vi beskytter imod, der er intet decideret sikkerhedsbrud, men mennesker kan ske at lave fejl, og omvejen at slette data i den rigtige rækkefølge er en lille pris at betale.

SQL understøtter også validering af data ved oprettelse. Dette gør den via *check constraints*. Et eksempel kan ses i booking tabellen, der kræver at antallet af døgn man lejer en bil, skal være et positivt tal.

```sql
constraint erDøgnOver0 check (døgn >= 0)
```

### Opgave 2

Udover relationelle forsikringer, kan der være mere komplekse forretningskrav som man også gerne vil forsikre. Et af disse krav er *Starttidspunkt for en booking skal være inden for åbningstid*. Et fornuftigt nok krav, som skal sikres i databasen, ikke applikationen. Der er to løsningsmuligheder for denne, et *check* og en *trigger*. Hvis det er muligt at nøjes med at *check* er det blevet valgt.

```sql
alter table Booking
add constraint erIndenforåbningstid check (datepart(hour, startdato) >= 6 and datepart(hour, startdato) < 20 and startdato > getdate())
```
Dette vil kontrollere, både ved oprettelse og opdatering, af starttidspunktet ligger inden for åbningstiderne.

Der er også krav om, at en booking ikke må ændres eller slettes indenfor 5 dage af den start. Her bliver det mere interessant. Der er følgende antagelse:
- Det er muligt at ændre en booking der ligger 4 uger i fremtiden, til at ligge i morgen, ligesom det er antaget at man godt kan oprette en booking til i morgen.
- Der er **ikke** muligt at ændre en booking i morgen, til om 4 uger.
- Ved ændring af en booking, skal bookingnummer forblive det samme

Dette kan kontrolleres ved hjælp af en trigger, eller to. Da det er tidspunktet før ændring der afgører om man får lov eller ej, kigges der i tabellen *deleted*.
```sql
if (select count(*) from deleted d where datediff(day, getdate(), d.startdato) <= 5) > 0
```
Derefter skal der opdateres iforhold til de nye data. Dette kan gøres ved at slette de gamle, og oprette de nye (i så fald kan nøjes med én trigger), men dette vil skifte bookingnummer på bookingen. Der er derfor valgt at lave to triggers, som henholdsvis opdatere og sletter.

Logikken for denne kunne være mere kompleks. Hvis tabeldesignet havde *KilometerVedStart* og *KilometerVedSlut* på bookingen, som nullable værdier, ville disse triggers skulle tage højde for hvilke attributter der havde ændret sig, da de da først er tilgængelige når bilen bliver afhentet og afleveret. Ved at *Afhentning* er sin egen tabel, kan forretningsreglen *Ingen ændring af booking indenfor 5 dage* blive simpelt overholdt.

### Opgave 4

En *stored procedure* som henter alle ledige biler på et bestemt tidspunkt, med en bestemt klasse og station. Fremgangsmåden her er simpel: 
  1. Find alle bookings som overlapper med det givne tidspunkt
  2. Tag bookingens tilhørende bil
  3. Tag alle biler som ikke er blandt de bookede biler
  4. Filtre også på klasse og station

En *subquery* er potentielt ikke optimal ydeevne, men dette kan forbedres med indexes.

### Opgave 5

For at finde indexes til databasen skal man kende to ting: Hvordan ser datamængde fordelingen ud, og hvilke queries der vil blive kørt.
Der vil blive taget udgangspunkt i følgende to queries:
- Find alle skader på en bil
- Den stored procedure fra opgave 4

#### Find alle skader på en bil

Dette er en simpel query, men der skal også tages hensyn til hvordan tabeldesignet er sat op. Disse ting går hånd i hånd. Det første spørgsmål er "Hvor mange biler har vi, og hvor mange skader får de"? Dette er relevant da SQL potentielt undgår at bruge indexet hvis dataene der ledes efter udgør en for stor del af det samlede data. Selv ved relativt lave mængder af data kan dette undviges, ved brug af et *clustered* index. 
Definitionen på en skade:
```sql
create table Skade(
	bil char(7) not null foreign key references Bil(registreringsnummer),
	beskrivelse nvarchar(255) not null,
	grad int not null
)
```

Som det kan ses her, har en skade en reference til en bil, men har ikke nogen *primary key*. Grunden til *bil* ikke er *primary key* er at den ikke må være unik, eftersom en bil kan have flere skader. Dette betyder dog, at skader er heap allokeret, og selv hvis datamængden er lille, kan det være langsomt at finde. En query for at finde alle skader på en bil kunne sådan her ud.
```sql
select s.beskrivelse 
from Skade s
join Bil b on s.bil = b.registreringsnummer
where b.registreringsnummer = 'GG12489'
```
Resultatet af denne simple query kræver unødvendigt mange reads.

> (20 rows affected)
> 
> Table 'Skade'. Scan count 1, logical reads **3483**, physical reads 0, page server reads 0, read-ahead reads 0, page server read-ahead reads 0, lob logical reads 0, lob physical reads 0, lob page server reads 0, lob read-ahead reads 0, lob page server read-ahead reads 0.

Ved at sætte et clustered index på *Skade* kan vi nedsætte dette drastisk.
```sql
create clustered index ix_skader on Skade(bil)
```
Samme query resultere nu i dette.

> (20 rows affected)
> 
> Table 'Skade'. Scan count 1, logical reads **2**, physical reads 0, page server reads 0, read-ahead reads 0, page server read-ahead reads 0, lob logical reads 0, lob physical reads 0, lob page server reads 0, lob read-ahead reads 0, lob page server read-ahead reads 0.

Alternativt kunne man lave en *pseudo primary key*, og et *non-clustered* index på bil, men så er det forhåbentligt ikke nok data til at indexet vil blive brugt. 

#### Find ledige biler

Samme spørgsmål skal stille her "Hvor mange biler har vi, og hvor mange bookinger har de?". Her er det ikke så fordelagtigt at lægge et *clustered* index på *bil*, da bookings også vil blive hentet for en kunde, eller for en given tidsperiode. Queryen ser således ud.
```sql
create procedure sp_ledigeBiler @station char(8), @klasse char(1), @startdato datetime, @døgn int
as
	select bil.registreringsnummer, bil.beskrivelse
	from Bil bil
	where 
		bil.klasse = @klasse and 
		bil.stationsnummer = @station and
		bil.registreringsnummer not in (select bil from Booking where booking.startdato <= dateadd(day, @døgn, @startdato) and dateadd(day, booking.døgn, booking.startdato) >= @startdato)
```
Dette gør den på følgende måde:

![uden index](https://github.com/ChrisWohlert/DatabaseEksamen/blob/main/ledige_biler_uden_index.png?raw=true)


> (2 rows affected)

> Table 'Booking'. Scan count 1, logical reads **28**, physical reads 0, page server reads 0, read-ahead reads 0, page server read-ahead reads 0, lob logical reads 0, lob physical reads 0, lob page server reads 0, lob read-ahead reads 0, lob page server read-ahead reads 0.

Vi kan se på billedet at der bliver lavet et scan over alle bookinger, og dette tager 69% af tiden. Derudover kan vi se den laver 28 reads. 28 reads er selvfølge et tal som variere alt efter hvor meget data der er, så det giver mere mening at se på hvordan et index giver en relativ forbedring.

Så der skal sættes et index på relationen mellem bil og booking.
```sql
create index ix_booking_bil on Booking (bil)
```
Efter dette, har intet ændret sig. Det vurderes at dette index ikke er godt nok til at blive brugt. For at bruge dette index, skal den gå igennem index-træet for at finde nøglen på en booking, derefter slår den op i det clustered index med den nøgle for selve bookingen. Dette er for meget til at den vurdere det fordelagtigt. Givet en anden komposition af data, vil dette index potentielt blive taget i brug, men det kan gøre bedre. Der er ikke brug for hele bookingen, kun bil, døgn og startdato.
```sql
create index ix_dato on Booking (bil, startdato, døgn)
```
Det er derfor muligt at cover de øvrige attributter som der er behov for. Ved at gøre dette behøves den ikke lave det ekstra opslag i det *clustered* index, den har alt det data den skal bruge, direkte i index leaf noden. 

![uden index](https://github.com/ChrisWohlert/DatabaseEksamen/blob/main/ledige_biler_med_index.png?raw=true)

> (2 rows affected)
> 
> Table 'Booking'. Scan count 2, logical reads **4**, physical reads 0, page server reads 0, read-ahead reads 0, page server read-ahead reads 0, lob logical reads 0, lob physical reads 0, lob page server reads 0, lob read-ahead reads 0, lob page server read-ahead reads 0.

Vi kan ser se den gør brug af indexet, ved at lave en Seek og navnet "ix_dato". Den bruger nu 58% af tiden i denne *subquery*, hvilket stadig er en del, men også en klar forbedring. Den laver også kun 4 reads nu, hvilket er en væsentligt nedgang fra 28.

Der findes potentielt større besparelser andre steder, men det er ikke kun hvor man kan gøre den største forskel der er vigtig, det er hvor det gør den største forskel for forretningen. At se ledige biler er det første en kunde vil be om, og et hurtigt svar er afgørende.

### Opgave 6

Til valg af isolation level, skal der typisk opveje data integritet imod samtidighed af handlinger. Hvor sandsynligt er det et problem opstår? Hvor stor er skaden hvis det opstår? Hvor kritisk er det, at brugeroplevelsen ikke bliver blokeret?

Samtidighedskontrol fungerer som et hierki, hvor man med mere og mere kontrol, får mere og mere blokering.

#### Applikation

Applikationen fungerer på følgende måde:

1. Åben en forbindelse til databasen
2. Start en transaction med Isolation Level Read Uncommitted
3. Execute stored procedure som henter ledige biler
4. Commit transaction
5. Luk forbindelse til database
6. Bruger vælger bil blandt de ledige biler præsenteret
7. Åben ny forbindelse til databasen
8. Start en ny transaction med Isolation Level Serializable
9. Execute query imod databasen som returner antal bookings den valgte bil har i det givet tidsrum
10. Hvis det tal ikke er 0 
   1.   Bilen er ikke længere ledig
   2.   Rollback transaction
11. Hvis det tal er 0, 
    1.  Brugeren bliver bedt om at bekræfte
    2.  Opret en ny booking i samme transaction
    3.  Commit transaction
12. Luk forbindelse til database

#### Optimistisk / Pessimistisk

Man kan vælge at holde en transaction åben for hele interaktionen, eller man kan vælge at splitte den op i to. Der medfølger visse ulemper hvis man vælger kun at have én transaction, hvor man læser ledige biler, vælge den man vil have, og opretter en booking. Fordelen er, at man ikke længere behøver at tjekke for om den valgte bil er ledig. Ulempen er, at man er nødt til at locke alle ledige biler til brugeren har valgt hvilken en de vil have. Altså, to brugeren kan ikke kigge på ledige biler på samme tid. Dette anses som uacceptabelt, og der er derfor valgt en løsning med to transactioner. Hertil skal nævnes, at man ved hjælp af Isolation Level Snapshot, kan komme uden om dette problem, hvor den i stedet for at sætte en lock på ledige biler, bare gemmer sin egen version af dem. Ved at splitte det op i to transactions, gives der både plads til at flere brugere har samtidighed mens forbindelsen ikke bliver brugt, og det giver mulighed for at sætte forskellige Isolation Level på de to transactions. 

#### Isolation Level

Når mange brugere bliver præsenteret for ledige biler på samme tid, skal det ikke gå ud over hinanden. En lav Isolation Level er derfor helt fint. Ved at bruge Isolation Level, *Read Uncommitted*, sikres det at brugere ikke bliver blokeret i at læse hvilke biler der er ledige. Dette betyder dog at der er risiko for *dirty reads*. Altså vil listen af ledige biler potential mangle en bil som er igang med at blive booket, men ikke er bekræftet endnu. Den anden bruger fortryder måske, og i så fald vil den blive rullet tilbage uden for den første bruger ser det. Dette fungere lidt som web shops, hvor ting i kurven er låst til dig, så andre ikke kan se dem.

Når der skal bookes, er det kritisk at den samme bil ikke bliver booket flere gange på samme tid. De forskellige *read* locks, sætter locks på den data de læser, men hvad med den data som ikke findes endnu? *Repeatable Read* sikrer sig data ikke bliver opdateret mens den læser, men den forhindrer ikke at data bliver oprettet, *Phantom read*. Selvom Snapshot Isolation gør det muligt for flere brugere at se ledige biler på samme tid, forhindrer den ikke at den samme bil bliver booket to gange. Snapshot Isolation laver en kopi af det relevante data, så der ikke ændres i det i levetiden af transaction, men den opfanger ikke hvis der er blevet oprettet nyt data. Det er derfor muligt med Snapshot Isolation at få to bookinger af samme bil på samme tid.

Isolation Level er sat til Serializable, det giver den stærkste sikkerhed, men der er også brugervendte problemer. Det er muligt at blive præsenteret for en bil som viser sig ikke at være ledig alligevel. Det gør også at flere kunder ikke kan bekræfte deres valg på samme tid. Dette er selvfølgelig ikke optimalt, og kan i virkeligheden nok løses med et *forced insert*. Hvor dataene bliver oprettet før brugeren bekræfter, og ved afkræftelse bliver de slettet igen.

# Bilag

## Bilag UML og Tabel diagram



## Bilag SQL

```sql


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
	bil char(7) not null foreign key references Bil(registreringsnummer), -- Clustered index er ikke på, da bil ikke er primary key, eftersom den ikke skal være unik.
	beskrivelse nvarchar(255) not null,
	grad int not null -- Bruges til at vurdere om bilen skal pensioneres, eller påskrives en rabat. Jo højere en grad, jo værre en skade, derved kan man summe alle graden af alle skader på en bil
	-- Det kan diskuteres om der skal være en nullable reference til Kunden, så det er muligt at få en skadeshistorik pø en kunde når de booker en bil. (Det vurderes at være uden for scope) (Nullable da skaden kan være forårsaget af andre en kunden)
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
	constraint erDøgnOver0 check (døgn >= 0)
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
add constraint erIndenforåbningstid check (datepart(hour, startdato) >= 6 and datepart(hour, startdato) < 20 and startdato > getdate())

go

drop trigger if exists booking_update_validation_trigger

go

-- En booking må ikke ændres hvis startdato er inden for 5 dage
create trigger booking_update_validation_trigger
on Booking
instead of UPDATE
as
	begin tran

	if (select count(*) from deleted d where datediff(day, getdate(), d.startdato) <= 5) > 0
	begin
		print('Error updating booking')
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
		
		commit
	end
	
go

drop trigger if exists booking_delete_validation_trigger

go

-- En booking må ikke slettes hvis startdato er inden for 5 dage
create trigger booking_delete_validation_trigger
on Booking
instead of DELETE
as
	begin tran

	if (select count(*) from deleted d where datediff(day, getdate(), d.startdato) <= 5) > 0
	begin
		print('Error deleting booking')
		rollback
	end
	else
	begin
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

commit tran

```

## Bilag C#

```csharp
using System;
using System.Data;
using System.Data.SqlClient;

namespace Biludlejning
{

    class Program
    {
        private const string ConnectionString =
            "Data Source=CHRISWOHLERTPC\\SQLEXPRESS;Initial Catalog=Biludlejning;"
            + "Integrated Security=true";

        static void Main(string[] args)
        {
            Console.WriteLine("Velkommen");

            Console.WriteLine("Indtast kundenummer");
            int kundenummer = int.Parse(Console.ReadLine());

            Console.WriteLine("Indtast stationsnummer");
            string stationsnummer = Console.ReadLine();

            Console.WriteLine("Indtast Ønsket klasse");
            string klasse = Console.ReadLine();

            Console.WriteLine("Indtast starttidspunkt");
            var starttidspunkt = DateTime.Parse(Console.ReadLine());

            Console.WriteLine("Indtast antal døgn");
            int døgn = int.Parse(Console.ReadLine());

            using (SqlConnection connection =
                         new SqlConnection(ConnectionString))
            {
                connection.Open();
                try
                {
                    LedigeBiler(stationsnummer, klasse, starttidspunkt, døgn, connection);
                }
                catch (Exception e)
                {
                    Console.WriteLine("Noget gik galt, prøv igen: " + e.Message);
                }
            }

            using (var connection = new SqlConnection(ConnectionString))
            {
                connection.Open();
                try
                {
                    string valgteBil = Console.ReadLine();
                    if (string.IsNullOrEmpty(valgteBil))
                        return;

                    BookBil(kundenummer, starttidspunkt, døgn, connection, valgteBil);
                }
                catch (Exception e)
                {
                    Console.WriteLine("Noget gik galt, prøv igen: " + e.Message);
                }
            }
        }

        private static void LedigeBiler(
            string stationsnummer,
            string klasse,
            DateTime starttidspunkt,
            int døgn,
            SqlConnection connection)
        {
            var tran = connection.BeginTransaction(IsolationLevel.ReadUncommitted);
            SqlCommand command = new SqlCommand("sp_ledigeBiler", connection)
            {
                CommandType = CommandType.StoredProcedure,
                Transaction = tran
            };
            command.Parameters.AddWithValue("@station", stationsnummer);
            command.Parameters.AddWithValue("@klasse", klasse);
            command.Parameters.AddWithValue("@startdato", starttidspunkt);
            command.Parameters.AddWithValue("@døgn", døgn);

            try
            {
                SqlDataReader reader = command.ExecuteReader();
                Console.WriteLine("\nLedige biler: ");

                while (reader.Read())
                {
                    Console.WriteLine("\t{0} | {1}",
                        reader[0], reader[1]);
                }
                reader.Close();

                Console.WriteLine("Skriv registreringsnummer for at booke");

                tran.Commit();
            }
            catch (Exception ex)
            {
                Console.WriteLine(ex.Message);
                tran.Rollback();
            }
        }

        private static void BookBil(
            int kundenummer,
            DateTime starttidspunkt,
            int døgn,
            SqlConnection connection,
            string valgteBil)
        {
            string bookingsBilHarIPeriodeQuery = @"
                select count(*) from Bil bil
                join Booking booking on booking.bil = bil.registreringsnummer
                where
                bil.registreringsnummer = @valgteBil and
                booking.startdato <= dateadd(day, @døgn, @startdato) and 
                dateadd(day, booking.døgn, booking.startdato) >= @startdato
            ";


            string bookingQuery = @"
                    insert into Booking (kundenummer, startdato, døgn, bil) values (@1, @2, @3, @4)
                ";

            var tran = connection.BeginTransaction(IsolationLevel.RepeatableRead);
            try
            {
                SqlCommand bookingsBilHarIPeriodeCommand = new SqlCommand(bookingsBilHarIPeriodeQuery, connection)
                {
                    Transaction = tran
                };
                bookingsBilHarIPeriodeCommand.Parameters.AddWithValue("@valgteBil", valgteBil);
                bookingsBilHarIPeriodeCommand.Parameters.AddWithValue("@startdato", starttidspunkt);
                bookingsBilHarIPeriodeCommand.Parameters.AddWithValue("@døgn", døgn);

                SqlDataReader reader = bookingsBilHarIPeriodeCommand.ExecuteReader();

                if (reader.Read())
                {
                    if ((int)reader[0] == 0)
                    {
                        reader.Close();

                        SqlCommand insertCommand = new SqlCommand(bookingQuery, connection)
                        {
                            Transaction = tran
                        };
                        insertCommand.Parameters.AddWithValue("@1", kundenummer);
                        insertCommand.Parameters.AddWithValue("@2", starttidspunkt);
                        insertCommand.Parameters.AddWithValue("@3", døgn);
                        insertCommand.Parameters.AddWithValue("@4", valgteBil);

                        insertCommand.ExecuteNonQuery();

                        Console.WriteLine($"Bekræft at du vil booke {valgteBil} d. {starttidspunkt}");
                        Console.ReadLine();

                        tran.Commit();

                        Console.WriteLine("Tak for bookingen");
                    }
                    else
                    {
                        reader.Close();
                        Console.WriteLine("Bil er ikke længere ledig");
                        tran.Rollback();
                    }
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine(ex.Message);
                tran.Rollback();
            }
        }
    }
}

```