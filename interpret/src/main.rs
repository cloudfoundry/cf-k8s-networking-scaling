extern crate askama;

use regex::Regex;
use std::collections::HashMap;
use std::fs::File;
use std::io::{self, prelude::*, BufReader};
use structopt::StructOpt;

use askama::Template;
#[derive(Template)]
#[template(path = "index.html")]

struct IndexTemplate {
    success: i32,
    total: i32,
    total_time: u64,
    cp_cps: f64,
}

#[derive(StructOpt)]
struct Cli {
    #[structopt(parse(from_os_str))]
    path: std::path::PathBuf,
}

struct User {
    start_time: u64,
    success_time: u64,
    end_time: u64,
}

fn process_users(path: std::path::PathBuf) -> io::Result<()> {
    let file = File::open(path).unwrap();
    let reader = BufReader::new(file);

    let mut users: HashMap<String, User> = HashMap::new();

    for line in reader.lines() {
        let re = Regex::new(r"(\d+),(\d+),(\w+)").unwrap();
        let line = line.unwrap();
        match re.captures(line.as_str()) {
            Some(caps) => {
                let this_time = caps.get(1).unwrap().as_str().parse::<u64>().unwrap();
                let user = users
                    .entry(caps.get(2).unwrap().as_str().to_string())
                    .or_insert(User {
                        start_time: 0,
                        success_time: 0,
                        end_time: 0,
                    });
                match caps.get(3).unwrap().as_str() {
                    "COMPLETED" => {
                        user.end_time = this_time;
                        ()
                    }
                    "SUCCESS" => {
                        user.success_time = this_time;
                        ()
                    }
                    "STARTED" => {
                        user.start_time = this_time;
                        ()
                    }
                    _ => (),
                }
            }
            None => (),
        }
    }

    let mut file = File::create("user_data.csv")?;
    file.write(b"user id, start time, success time, nanoseconds to first success, completion time, nanoseconds to last error\n")?;
    let mut total = 0;
    let mut succeeded = 0;
    let mut start = std::u64::MAX;
    let mut end = 0;
    for (index, times) in users.iter() {
        total += 1;

        if times.end_time == 0 || times.success_time == 0 {
            println!("User {} did not complete.", index.to_string());
        } else if times.start_time == 0 {
            println!("Something terrible happened to User {}", index.to_string());
        } else {
            succeeded += 1;

            if end < times.end_time {
                end = times.end_time;
            }
            if start > times.start_time  {
                start = times.start_time;
            }

            write!(file, "{}, {}, {}, {}, {}, {}\n", index,
                times.start_time, times.success_time, times.success_time - times.start_time, times.end_time, times.end_time - times.start_time)?;
        }
    }

    println!("{} {}", start, end);

    let index = IndexTemplate {
        cp_cps: ((total as f64 / (end - start) as f64) * 1000.0 * 1000.0 * 1000.0 * 100.0).round() / 100.0,
        total_time: (end - start) / (1000 * 1000 * 1000),
        success: succeeded,
        total: total,
    };

    let mut file = File::create("index.html")?;
    file.write_all(index.render().unwrap().as_bytes())?;

    Ok(())
}

fn main() {
    let args = Cli::from_args();
    process_users(args.path).expect("Something went wrong with user logs");
}
