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
            int kundenummer = 1000017; // int.Parse(Console.ReadLine());

            Console.WriteLine("Indtast stationsnummer");
            string stationsnummer = "82106284"; // Console.ReadLine();

            Console.WriteLine("Indtast Ønsket klasse");
            string klasse = "B"; // Console.ReadLine();

            Console.WriteLine("Indtast starttidspunkt");
            var starttidspunkt = DateTime.Parse("2022/07/25 10:00"); // DateTime.Parse(Console.ReadLine());

            Console.WriteLine("Indtast antal døgn");
            int døgn = 2; // int.Parse(Console.ReadLine());

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
