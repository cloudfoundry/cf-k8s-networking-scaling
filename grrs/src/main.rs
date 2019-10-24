use histogram::Histogram;
use regex::Regex;
use std::collections::HashMap;
use std::fs::File;
use std::io::{self, prelude::*, BufReader};
use structopt::StructOpt;

/// Search for a pattern in a file and display the lines that contain it.
#[derive(StructOpt)]
struct Cli {
    /// The path to the file to read
    #[structopt(parse(from_os_str))]
    path: std::path::PathBuf,
}

struct User {
    start_time: i32,
    end_time: i32,
}

fn main() -> io::Result<()> {
    let args = Cli::from_args();

    let file = File::open(&args.path).unwrap();
    let reader = BufReader::new(file);
    // let content = std::fs::read_to_string(&args.path).expect("could not read file");

    let mut users: HashMap<String, User> = HashMap::new();

    for line in reader.lines() {
        let re = Regex::new(r"(\d{10}) USER (\d+) (\w+)").unwrap();
        let line = line.unwrap();
        match re.captures(line.as_str()) {
            Some(caps) => {
                let this_time = caps.get(1).unwrap().as_str().parse::<i32>().unwrap();
                let user = users
                    .entry(caps.get(2).unwrap().as_str().to_string())
                    .or_insert(User {
                        start_time: 0,
                        end_time: 0,
                    });
                match caps.get(3).unwrap().as_str() {
                    "COMPLETED" => {
                        user.end_time = this_time;
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

    let mut histogram = Histogram::new();
    let mut total = 0;
    let mut succeeded = 0;
    for (index, times) in users.iter() {
        total += 1;
        // println!(
        //     "user {} took {} seconds",
        //     index,
        //     times.end_time - times.start_time
        // );
        if times.end_time == 0 {
            println!("User {} did not complete.", index.to_string());
        } else if times.start_time == 0 {
            println!("Something terrible happened to User {}", index.to_string());
        } else {
            succeeded += 1;
            histogram.increment((times.end_time - times.start_time) as u64);
        }
    }

    println!(
        "Percentiles: p68: {}, p90: {}, p99: {}, p99.9: {}, p99.99: {}, max: {}",
        histogram.percentile(68.0).unwrap(),
        histogram.percentile(90.0).unwrap(),
        histogram.percentile(99.0).unwrap(),
        histogram.percentile(99.9).unwrap(),
        histogram.percentile(99.99).unwrap(),
        histogram.maximum().unwrap(),
    );

    println!(
        "{} of {} users successfully completed their tasks",
        total.to_string(),
        succeeded.to_string()
    );

    Ok(())
}
