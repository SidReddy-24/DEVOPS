const db = require("./config/db");
const express = require("express");
const path = require("path");

const app = express();

app.use(express.urlencoded({ extended: true }));
app.use(express.json());

app.use(express.static("public"));

app.set("view engine", "ejs");
app.set("views", path.join(__dirname, "views"));

app.get("/", (req, res) => {
    res.render("login");
});

const PORT = 3000;

app.get("/admin",(req,res)=>{
    res.render("admin");
});

app.get("/doctor",(req,res)=>{
    res.render("doctor");
});

app.get("/patient",(req,res)=>{
    res.render("patient");
});

app.post("/login",(req,res)=>{

    const email=req.body.email;
    const password=req.body.password;

    const sql="SELECT * FROM users WHERE email=? AND password=?";

    db.query(sql,[email,password],(err,result)=>{

        if(err){
            console.log(err);
            return;
        }

        if(result.length==0){

            res.send("Invalid Login");

        }else{

            const role=result[0].role;

            if(role=="admin"){
                db.query(
                            "INSERT INTO audit_logs(user_id,action) VALUES(?,?)",
                                [result[0].id,"User Logged In"]
                        );

                res.redirect("/admin");

            }

            else if(role=="doctor"){

                res.redirect("/doctor");

            }

            else{

                res.redirect("/patient");

            }

        }

    });

});

app.get("/add-user",(req,res)=>{
    res.render("add-user");
});

app.post("/add-user",(req,res)=>{

    const {name,email,password,role}=req.body;

    const sql=
    "INSERT INTO users(name,email,password,role) VALUES(?,?,?,?)";

    db.query(sql,[name,email,password,role],(err)=>{

        if(err){

            console.log(err);

        }else{

            res.redirect("/users");

        }

    });

});

app.get("/users",(req,res)=>{

    db.query("SELECT * FROM users",(err,result)=>{

        if(err){

            console.log(err);

        }else{

            res.render("users",{users:result});

        }

    });

});

app.get("/add-user", (req, res) => {
    res.render("add-user");
});

app.post("/add-user", (req, res) => {
    const { name, email, password, role } = req.body;

    const sql =
        "INSERT INTO users(name,email,password,role) VALUES(?,?,?,?)";

    db.query(sql, [name, email, password, role], (err) => {
        if (err) {
            console.log(err);
            res.send("Error adding user");
        } else{

    db.query(
        "INSERT INTO audit_logs(user_id,action) VALUES(?,?)",
        [1,"Admin Created User"]
    );

    res.redirect("/users");

}
    });
});

app.get("/users", (req, res) => {
    db.query("SELECT * FROM users", (err, result) => {
        if (err) {
            console.log(err);
            res.send("Database Error");
        } else {
            res.render("users", { users: result });
        }
    });
});

app.get("/book-appointment",(req,res)=>{

    res.render("book-appointment");

});

app.post("/book-appointment",(req,res)=>{

    const {patient_id,doctor_id,appointment_date}=req.body;

    const sql=

    `INSERT INTO appointments
    (patient_id,
    doctor_id,
    appointment_date,
    status)

    VALUES(?,?,?,'scheduled')`;

    db.query(sql,

    [patient_id,doctor_id,appointment_date],

    (err)=>{

        if(err){

            console.log(err);

        }

        else{

    db.query(
        "INSERT INTO audit_logs(user_id,action) VALUES(?,?)",
        [patient_id,"Appointment Booked"]
    );

    res.send("Appointment Booked!");

}

    });

});

app.get("/appointments",(req,res)=>{

    db.query(

    "SELECT * FROM appointments",

    (err,result)=>{

        if(err){

            console.log(err);

        }

        else{

            res.render(

            "appointments",

            {appointments:result}

            );

        }

    });

});

app.get("/add-record",(req,res)=>{

    res.render("add-record");

});

app.post("/add-record",(req,res)=>{

const {
patient_id,
doctor_id,
diagnosis,
prescription
}=req.body;

const sql=

`INSERT INTO medical_records

(patient_id,
doctor_id,
diagnosis,
prescription,
visit_date)

VALUES(?,?,?,?,CURDATE())`;

db.query(sql,

[
patient_id,
doctor_id,
diagnosis,
prescription
],

(err)=>{

if(err){

console.log(err);

}

else{

    db.query(
        "INSERT INTO audit_logs(user_id,action) VALUES(?,?)",
        [doctor_id,"Medical Record Added"]
    );

    res.send("Medical Record Added!");

}

});

});

app.get("/my-records",(req,res)=>{

db.query(

"SELECT * FROM medical_records",

(err,result)=>{

if(err){

console.log(err);

}

else{

res.render(

"medical-records",

{
records:result
}

);

}

});

});

app.get("/audit",(req,res)=>{

db.query(

"SELECT * FROM audit_logs",

(err,result)=>{

if(err){

console.log(err);

}

else{

res.render(
"audit",
{logs:result}
);

}

});

});

app.get("/audit",(req,res)=>{

    db.query(
        "SELECT * FROM audit_logs",
        (err,result)=>{

            if(err){

                console.log(err);

            }

            else{

                res.render(
                    "audit",
                    {logs:result}
                );

            }

        }
    );

});

app.listen(PORT, () => {
    console.log(`🚀 Server running at http://localhost:${PORT}`);
});