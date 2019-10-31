extern crate askama;

use histogram::Histogram;
use regex::Regex;
use std::collections::HashMap;
use std::fs::File;
use std::io::{self, prelude::*, BufReader};
use structopt::StructOpt;

use askama::Template;
#[derive(Template)]
#[template(path = "index.html")]

struct IndexTemplate<'a> {
    success: i32,
    total: i32,
    sgram: &'a str,
    cgram: &'a str,
    dgram: &'a str,
    total_time: u64,
    cp_cps: f64,
}

#[derive(StructOpt)]
struct Cli {
    #[structopt(parse(from_os_str))]
    path: std::path::PathBuf,
}

struct User {
    start_time: i32,
    success_time: i32,
    end_time: i32,
}

fn gram_to_csv(gram: Histogram) -> String {
    assert_ne!(
        gram.entries(),
        0,
        "It is not possible to print a histogram with no data"
    );
    return format!(
        "{},{},{},{},{},{}",
        gram.percentile(68.0).unwrap(),
        gram.percentile(90.0).unwrap(),
        gram.percentile(99.0).unwrap(),
        gram.percentile(99.9).unwrap(),
        gram.percentile(99.99).unwrap(),
        gram.maximum().unwrap(),
    );
}

fn gram_to_string(gram: &Histogram) -> String {
    assert_ne!(
        gram.entries(),
        0,
        "It is not possible to print a histogram with no data"
    );
    return format!(
        "p68: {}, p90: {}, p99: {}, p99.9: {}, p99.99: {}, max: {}",
        gram.percentile(68.0).unwrap(),
        gram.percentile(90.0).unwrap(),
        gram.percentile(99.0).unwrap(),
        gram.percentile(99.9).unwrap(),
        gram.percentile(99.99).unwrap(),
        gram.maximum().unwrap(),
    );
}

fn process_users(path: std::path::PathBuf) -> io::Result<()> {
    let file = File::open(path).unwrap();
    let reader = BufReader::new(file);

    let mut users: HashMap<String, User> = HashMap::new();

    for line in reader.lines() {
        let re = Regex::new(r"(\d{10}),(\d+),(\w+)").unwrap();
        let line = line.unwrap();
        match re.captures(line.as_str()) {
            Some(caps) => {
                let this_time = caps.get(1).unwrap().as_str().parse::<i32>().unwrap();
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

    let mut success_gram = Histogram::new();
    let mut complete_gram = Histogram::new();
    let mut diff_gram = Histogram::new();
    let mut total = 0;
    let mut succeeded = 0;
    let mut start: f64 = 9999999999.0;
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
            if start > times.start_time as f64 {
                start = times.start_time as f64;
            }

            success_gram
                .increment((times.success_time - times.start_time) as u64)
                .expect("could not increment");
            complete_gram
                .increment((times.end_time - times.start_time) as u64)
                .expect("could not increment");
            diff_gram
                .increment((times.end_time - times.success_time) as u64)
                .expect("could not increment");
        }
    }

    println!("{} {}", start, end);

    let sgram = gram_to_string(&success_gram);
    let cgram = gram_to_string(&complete_gram);
    let dgram = gram_to_string(&diff_gram);

    let index = IndexTemplate {
        cp_cps: (total as f64 / (end as f64 - start)),
        total_time: (end as u64 - start as u64),
        success: succeeded,
        total: total,
        sgram: sgram.as_str(),
        cgram: cgram.as_str(),
        dgram: dgram.as_str(),
    };

    let mut file = File::create("index.html")?;
    file.write_all(index.render().unwrap().as_bytes())?;

    let mut file = File::create("controlplane_latency.csv")?;
    file.write(b"event, 68, 90, 99, 99.9, 99.99, 100\n")?;
    write!(file, "success, {}\n", gram_to_csv(success_gram))?;
    write!(file, "complete, {}\n", gram_to_csv(complete_gram))?;

    Ok(())
}

fn main() {
    let args = Cli::from_args();
    process_users(args.path).expect("Something went wrong with user logs");
}
