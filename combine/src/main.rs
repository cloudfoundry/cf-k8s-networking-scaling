use regex::Regex;
use std::error::Error;
use std::fs::{self, File, OpenOptions};
use std::io::{prelude::*, BufReader};
use structopt::StructOpt;

// This script will take several folders of results (up to about 100) and combine them into a
// single summary page + summary CSVs for R to turn into SVGs.

// Relevant CSV files:
// - cpustats.csv (created from cpustats.log by interpret)  <-- TODO
// - memstats.csv (created from memstats.log by interpret)  <-- TODO
// - networkstats.csv (created from networkstats.log by interpret)  <-- TODO
// - dataload.csv (created by apib script)
// - gatewaystats.csv (created by gateway memory monitoring script)
// - howmanypilots.csv (created by ?? script)
// - importanttimes.csv (created by experiment script)
// - rawlatencies.txt (created by apib script)
// - sidecarstats.csv (created by sidecar memory monitoring script)
// - user_data.csv (created from user.log by interpret)
// - vars.sh (copied by experiment, should be identical for each test in experiment)

// We can use Crate csv to read/write data as csvs

// Our goal is to have graphs over time with many  faded lines and one representative darker line.
// R can handle picking one to make darker
// This script needs to normalize the timestamps to nanoseconds since start of experiment and
// combine the data into a summary csv, where each row is labelled with test run id.

// Usage: combine onehundred
// Each run of this experiment will be in folders underneath.

// Get the CLI arg, which will be the containing folder.
// Use the CLI arg to get a list of the nested folders.
// For each folder, open some CSV files and add the data to our sets of data.
// Use all the data to output combined CSVs and a summary index.html to a new folder
// (e.g. oneundred-summary).

// For each file, we need to remove the header, add a new column for test-run-id, then just concat

// Get list of folder
// From first folder, grab header lines
// Start output CSVs with headers
// For each folder,
// Open file, remove header line, convert timestamps to experiment time, write to combined CSV, prepending the new id to each
// line
//
//
// Write a summary index.html at the top level
#[derive(StructOpt)]
struct Cli {
    #[structopt(parse(from_os_str))]
    path: std::path::PathBuf,
}

fn setup_headers(
    output_folder: &std::path::PathBuf,
    input_folder: &std::fs::DirEntry,
    filenames: Vec<&str>,
) -> Result<(), Box<dyn Error>> {
    for filename in filenames.iter() {
        let mut source_path = input_folder.path();
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

fn get_start_time(input_folder: &std::fs::DirEntry) -> Result<u64, Box<dyn Error>> {
    let mut source_path = input_folder.path();
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

// For each filename, take the matching file in the input folder and alter the timestamps to treat
// 'get_start_time' as zero, then append them to the matching output folder file, with each line
// prepended by the experiment id.
fn add_runid_and_normalize_timestamp(
    output_folder: &std::path::PathBuf,
    input_folder: &std::fs::DirEntry,
    filenames: [&str; 5],
    run_id: u32,
) -> Result<(), Box<dyn Error>> {
    let zero_timestamp = match get_start_time(input_folder){
        Ok(t) => t,
        Err(e) => return Err(format!("failed to get zero timestamp because {}", e))?,
    };
    for filename in filenames.iter() {
        let mut source_path = input_folder.path();
        source_path.push(filename);
        let mut dest_path = output_folder.clone();
        dest_path.push(filename);
        let mut dest_file = match OpenOptions::new().append(true).open(&dest_path) {
            Ok(f) => f,
            Err(e) => return Err(format!("failed to open {} because {}; expected headers to have already been inserted",
                    dest_path.to_str().ok_or("could not print filepath we couldn't open")?, e))?
        };

        let source_file = match File::open(&source_path) {
            Ok(f) => f,
            Err(e) => return Err(format!("failed to open source file {} because {}",
                    dest_path.to_str().ok_or("could not print filepath we couldn't open")?, e))?
        };
        let reader = BufReader::new(source_file);
        for (index, line) in reader.lines().enumerate() {
            let line = line?;
            if index == 0 {
                // Skip the first line because they are the headers.
                continue;
            }
            let re = Regex::new(r"(\d+),(.+)")?;
            let captures = re.captures(line.as_str()).ok_or(format!(
                "regex ({}) did not match on line {}: {}",
                re.as_str(),
                index,
                line.as_str()
            ))?;
            let this_time = captures
                .get(1)
                .ok_or("missing first capture group (the timestamp)")?
                .as_str()
                .parse::<u64>()?;
            let rest_of_line = captures
                .get(2)
                .ok_or("missing rest of line (after timestamp)")?
                .as_str();
            let converted_timestamp = match this_time.overflowing_sub(zero_timestamp) {
                (result, false) => result,
                (wrapped, true) => {
                    println!(
                        "Warning: timestamp was {} milliseconds before the start of the experiment",
                        (std::u64::MAX - wrapped) / (1000 * 1000)
                    );
                    0
                }
            };

           match write!(
                dest_file,
                "{}, {}, {}\n",
                run_id, converted_timestamp, rest_of_line
            ) {
               Ok(()) => (),
               Err(e) => return Err(format!("failed to write line {} to {} because {}", index, dest_path.to_str().ok_or("could not print filepath we couldn't open")?, e))?,
           };
        }
    }
        Ok(())
}

// For each filename, take the matching file in the input folder and prepend each line with the
// runid. Append each line to the matching output folder file.
fn add_runid(
    output_folder: &std::path::PathBuf,
    input_folder: &std::fs::DirEntry,
    filenames: [&str; 1],
    run_id: u32,
) -> Result<(), Box<dyn Error>> {
    for filename in filenames.iter() {
        let mut source_path = input_folder.path();
        source_path.push(filename);
        let mut dest_path = output_folder.clone();
        dest_path.push(filename);
        let mut dest_file = OpenOptions::new().append(true).open(dest_path)?;

        let source_file = File::open(source_path)?;
        let reader = BufReader::new(source_file);
        for (index, line) in reader.lines().enumerate() {
            let line = line?;
            if index == 0 {
                // Skip the first line because they are the headers.
                continue;
            }
            write!(dest_file, "{}, {}\n", run_id, line.as_str())?;
        }
    }
    Ok(())
}

fn main() -> Result<(), Box<dyn Error>> {
    let filenames_that_start_with_timestamps = [
        //"cpustats.csv",
        //"memstats.csv",
        //"networkstats.csv",
        "dataload.csv",
        "gatewaystats.csv",
        "howmanypilots.csv",
        "sidecarstats.csv",
        "importanttimes.csv",
    ];

    let filenames_without_timestamps = ["rawlatencies.txt"];

    let filenames_with_many_timestamps = [
        "user_data.csv",      // contains multipe timestamps per line
    ];

    // special files
    //"vars.sh" <- TODO need to check if they're all the same

    let args = Cli::from_args();
    let toppath = args.path;
    let mut count = 0;
    // Get list of folders
    for (index, folder) in fs::read_dir(&toppath)?.enumerate() {
        let folder = folder?;
        let folder_path = folder.path();

        if !folder.metadata()?.is_dir() {
            continue;
        }
        if count == 0 {
            count += 1;
            setup_headers(
                &toppath,
                &folder,
                filenames_that_start_with_timestamps.iter().chain(filenames_without_timestamps.iter()).chain(filenames_with_many_timestamps.iter()).cloned().collect()
                ).expect(format!(
                    "Failed to setup headers in combined CSVs based on {}",
                    folder_path.to_str().ok_or("failed to read folder path in order to print failed-to-setup-headers error")?
                ).as_str(),
            );
        }
        println!(
            "Processing {}...",
            folder_path
                .to_str()
                .ok_or("could not print folder path in status message")?
        );
        add_runid_and_normalize_timestamp(&toppath, &folder, filenames_that_start_with_timestamps, index as u32).expect(
            format!(
                "Something went wrong processing {}",
                folder_path.to_str().ok_or("failed to read folder path in order to print something-went-wrong-while-processing error")?
            )
            .as_str(),
        );
        add_runid(
            &toppath,
            &folder,
            filenames_without_timestamps,
            index as u32
            ).expect(
            format!(
                "Something went wrong processing {}",
                folder_path.to_str().ok_or("failed to read folder path in order to print something-went-wrong-while-processing error")?
            )
            .as_str(),
        );
        //combine_userdata(&toppath, &folder);
        //combine_importanttimes(&toppath, &folder);
    }

    Ok(())
}