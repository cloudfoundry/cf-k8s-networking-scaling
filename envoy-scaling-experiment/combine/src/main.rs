extern crate askama;
use regex::Regex;
use std::error::Error;
use std::fs::{self, File, OpenOptions};
use std::io::{prelude::*, BufReader};
use std::thread;
use structopt::StructOpt;

use askama::Template;
#[derive(Template)]
#[template(path = "index.html")]

struct IndexTemplate {
    tests: Vec<String>,
    files: Vec<String>,
    vars: String,
}

// This script will take several folders of results (up to about 100) and combine them into a
// single summary page + summary CSVs for R to turn into SVGs.

// Relevant CSV files:
// - importanttimes.csv (created by experiment script)
// - cpustats.csv
// - memstats.csv
// - networkstats.csv
// - gatewaystats.csv
// - sidecarstats.csv
// - vars.sh (copied by experiment, should be identical for each test in experiment)

// This script needs to normalize the timestamps to nanoseconds since start of experiment and
// combine the data into a summary csv, where each row is labelled with test run id.
// For each file, we need to remove the header, fix the timestmp,  add a new column for test-run-id, then just concat

// Get list of folders
// From first folder, grab header lines
// Start output CSVs with headers
// For each folder,
//   Open file, remove header line, convert timestamps to experiment time, write to combined CSV, prepending the new id to each line
// Write a summary index.html at the top level

#[derive(StructOpt)]
struct Cli {
    #[structopt(parse(from_os_str))]
    path: std::path::PathBuf,
}

// For each filename in filenames, open that file in input_folder and copy the first line into a
// file of the same name in output_folder
// Will return an error if it cannot open a filename in input_folder
fn setup_headers(
    output_folder: &std::path::PathBuf,
    input_folder: &std::path::PathBuf,
    filenames: Vec<&str>,
) -> Result<(), Box<dyn Error>> {
    for filename in filenames.iter() {
        let mut source_path = input_folder.clone();
        source_path.push(filename);
        let mut dest_path = output_folder.clone();
        dest_path.push(filename);

        let source_file = match File::open(&source_path) {
            Ok(file) => file,
            Err(e) => {
                return Err(format!(
                    "failed to open {}: {}",
                    source_path
                        .to_str()
                        .ok_or("failed to call to_str on source_path when we failed to open it")?,
                    e
                ))?
            }
        };
        let mut reader = BufReader::new(source_file);
        let mut headers: String = "".to_string();
        reader.read_line(&mut headers)?;

        let mut dest_file = File::create(dest_path)?;
        write!(dest_file, "runID, {}", headers)?;
    }
    Ok(())
}

fn get_start_time(input_folder: &std::path::PathBuf) -> Result<u64, Box<dyn Error>> {
    let mut source_path = input_folder.clone();
    source_path.push("importanttimes.csv");
    let source_file = match File::open(source_path) {
        Ok(file) => file,
        Err(err) => return Err(err.into()),
    };
    let mut reader = BufReader::new(source_file);
    let mut _headers: String = "".to_string();
    reader.read_line(&mut _headers)?;
    let mut first_line: String = "".to_string();
    reader.read_line(&mut first_line)?;
    let re = Regex::new(r"(\d+),.+")?;
    let captures = re
        .captures(first_line.as_str())
        .ok_or(format!("regex did not match on {}", first_line.as_str()))?;
    Ok(captures
        .get(1)
        .ok_or("could not capture timestamp")?
        .as_str()
        .parse::<u64>()?)
}

fn add_runid_and_normalize_file(
    output_file: &mut std::fs::File,
    input_reader: std::io::BufReader<std::fs::File>,
    run_id: usize,
    zero_timestamp: u64,
) -> Result<(), Box<dyn Error>> {
    for (index, line) in input_reader.lines().enumerate() {
        let line = line?;
        if index == 0 {
            // Skip the first line because they are the headers.
            continue;
        }
        let re = Regex::new(r"(\d+),(.+)")?;
        match re.captures(line.as_str()) {
            Some(captures) => {
                let this_time = captures
                    .get(1)
                    .ok_or("missing first capture group (the timestamp)")?
                    .as_str()
                    .parse::<u64>()?;
                let rest_of_line = captures
                    .get(2)
                    .ok_or("missing rest of line (after timestamp)")?
                    .as_str();
                let converted_timestamp = convert_or_warn(zero_timestamp, this_time);

                match write!(
                    output_file,
                    "{}, {}, {}\n",
                    run_id, converted_timestamp, rest_of_line
                ) {
                    Ok(()) => (),
                    Err(e) => return Err(format!("failed to write line {} because {}", index, e))?,
                }
            }

            None => println!(
                "regex({}) did not match on line {}, which is '{}'",
                re.as_str(),
                index,
                line.as_str()
            ),
        };
    }

    Ok(())
}

// For each filename, take the matching file in the input folder and alter the timestamps to treat
// 'get_start_time' as zero, then append them to the matching output folder file, with each line
// prepended by the experiment id.
fn add_runid_and_normalize_timestamp(
    output_folder: &std::path::PathBuf,
    input_folders: &Vec<std::path::PathBuf>,
    filename: &str,
) -> Result<(), Box<dyn Error>> {
    for (runid, inputfolder) in input_folders.iter().enumerate() {
        let zero_timestamp = match get_start_time(inputfolder) {
            Ok(t) => t,
            Err(e) => return Err(format!("failed to get zero timestamp because {}", e))?,
        };

        let mut dest_path = output_folder.clone();
        dest_path.push(filename);
        let mut dest_file = match OpenOptions::new().append(true).open(&dest_path) {
            Ok(f) => f,
            Err(e) => {
                return Err(format!(
                    "failed to open {} because {}; expected headers to have already been inserted",
                    dest_path
                        .to_str()
                        .ok_or("could not print filepath we couldn't open")?,
                    e
                ))?
            }
        };
        let mut source_path = inputfolder.clone();
        source_path.push(filename);

        let source_file = match File::open(&source_path) {
            Ok(f) => f,
            Err(e) => {
                return Err(format!(
                    "failed to open source file {} because {}",
                    dest_path
                        .to_str()
                        .ok_or("could not print filepath we couldn't open")?,
                    e
                ))?
            }
        };
        let reader = BufReader::new(source_file);
        add_runid_and_normalize_file(&mut dest_file, reader, runid, zero_timestamp)?;
    }
    println!("    - Finished {}", filename);

    Ok(())
}

// Converts an absolute timestamp to a timestamp relative to a given zero time
//   If the timestamp happens before the provided zero, print a warning to stdout
//   and return 0 because time travel is illegal round these parts
fn convert_or_warn(zero: u64, time: u64) -> u64 {
    match time.overflowing_sub(zero) {
        (result, false) => return result,
        (wrapped, true) => {
            println!(
                "Warning: timestamp ({}) was {} milliseconds before the start of the experiment ({})",
                time,
                (std::u64::MAX - wrapped) / (1000 * 1000),
                zero
            );
            return 0;
        }
    };
}

fn main() -> Result<(), Box<dyn Error>> {
    let filenames_that_start_with_timestamps = [
        "cpustats.csv",
        "envoyclusters.csv",
        //"endpoints_arrival.csv",
        //"envoy_cluster_update_attempts.csv",
        //"envoy_cluster_update_successes.csv",
        "gatewaystats.csv",
        "ifstats.csv",
        "importanttimes.csv",
        "jaeger.csv",
        "memstats.csv",
        "nodemon.csv",
        "nodes4pods.csv",
        "podalive.csv",
        "route-status.csv",
        //"routes_arrival.csv",
    ];

    //TODO should check if vars.sh are all the same

    let args = Cli::from_args();
    let toppath = args.path;

    let mut testnames: Vec<String> = vec![];
    let mut filenames: Vec<String> = vec![];
    let mut folderpaths: Vec<std::path::PathBuf> = vec![];

    // Get list of folders
    println!("Finding folder names");
    for folder in fs::read_dir(&toppath)? {
        let folder = folder?;
        let folder_path = folder.path();

        if !folder.metadata()?.is_dir() {
            continue;
        }

        // Get the path to each test folder (for collecting files)
        folderpaths.push(folder_path.clone());
        // Get the name of each test folder for index.html listing
        testnames.push(format!(
            "{}",
            folder_path
                .file_name()
                .expect("let me make my own mistakes rust")
                .to_string_lossy()
        ));
    }

    // Do once
    // Get vars.sh for index.html
    let mut vars_path = folderpaths[0].clone();
    vars_path.push("vars.sh");
    let vars = fs::read_to_string(vars_path)?;

    // Create all top-level CSV files and setup headers
    setup_headers(
        &toppath,
        &folderpaths[0],
        filenames_that_start_with_timestamps
            .iter()
            .cloned()
            .collect(),
    )
    .expect(
        format!(
            "Failed to setup headers in combined CSVs based on {}",
            folderpaths[0].to_str().ok_or(
                "failed to read folder path in order to print failed-to-setup-headers error"
            )?
        )
        .as_str(),
    );

    let mut handles = vec![];

    // For each file, spawn a thread
    for filename in filenames_that_start_with_timestamps.iter() {
        // Make a copy of all the data we need, so we can be independent
        let f = filename.clone();
        let fs = folderpaths.clone();
        let tp = toppath.clone();
        handles.push(thread::Builder::new().name(filename.to_string()).spawn(move || {
            println!("Processing {}...", f);
            add_runid_and_normalize_timestamp(&tp, &fs, f)
                .expect(format!("Something went wrong processing {}", f).as_str());
        }).unwrap());
    }

    // wait for processing to finish
    for handle in handles {
        handle
            .join()
            .expect("Something went wrong waiting for thread");
    }

    // collect names of non-directory files
    for file in fs::read_dir(&toppath)? {
        let file = file?;
        let file_path = file.path();

        if !file.metadata()?.is_dir() {
            filenames.push(format!(
                "{}",
                file_path
                    .file_name()
                    .expect("let me make my own mistakes rust")
                    .to_string_lossy()
            ));
        }
    }

    // Create a summary index.html
    let index = IndexTemplate {
        tests: testnames,
        files: filenames,
        vars: vars,
    };
    let mut file = File::create("index.html")?;
    file.write_all(index.render().unwrap().as_bytes())?;

    println!("All done.");
    Ok(())
}
