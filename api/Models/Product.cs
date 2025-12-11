namespace predicthrAPI.Models
{

    public class FlightReportRecord
    {
        // Example properties - replace with actual fields from your SP's result set
        public string report_name { get; set; }
        public string client_id { get; set; }
        public DateTime asof_date { get; set; }
        public string emp_id { get; set; }
        public string department { get; set; }
        public string role { get; set; }
        public decimal? flight_score { get; set; }
        public string reasons { get; set; }
        public string intervention { get; set; }
        public string baseline_range { get; set; }
        public string recent_range { get; set; }
    }




    // New Model for the Request Body
    public class ClientUploadRequest
    {
        // מזהה הלקוח (חובה)
        public string ClientId { get; set; }

        // קובץ CSV שמועלה מה-Frontend
        public IFormFile CsvFile { get; set; }

        // האם השורה הראשונה היא Header
        public bool HasHeader { get; set; } = true;

        // Row terminator — נשאר כמו קודם
        public string RowTerminator { get; set; } = "\n";

        // ⭐ חדש — תמיכה בפורמט תאריך
        // אפשרי: auto, yyyy-mm-dd, mm/dd/yyyy, dd/mm/yyyy ...
        public string DateFormat { get; set; } = "auto";
    }


}