const mysql = require("mysql2");

const db = mysql.createConnection({
    host:process.env.DB_HOST || "localhost",
    user:process.env.DB_USER || "root",
    password:process.env.DB_PASSWORD || "",
    database:process.env.DB_NAME || "ehr_platform",
});

db.connect((err) => {
    if (err) {
        console.log("❌ MySQL Connection Failed");
        console.log(err.message);
    } else {
        console.log("✅ MySQL Connected");
    }
});

module.exports = db;
