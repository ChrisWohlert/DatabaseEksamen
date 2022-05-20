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
![alt text](https://github.com/ChrisWohlert/DatabaseEksamen/blob/master/ledige_biler_uden_index.png?raw=true)
