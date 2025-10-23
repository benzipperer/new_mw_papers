# Install and load packages
packages <- c("openalexR", "dplyr", "readr", "purrr", "tidyr")
for (pkg in packages) {
  if (!require(pkg, character.only = TRUE)) {
    install.packages(pkg, repos = "https://cran.rstudio.com/")
  }
}

library(openalexR)
library(dplyr)
library(readr)
library(purrr)
library(tidyr)

# Set email for polite API access
openalex_email <- Sys.getenv("OPENALEX_EMAIL", "agent@example.com")
options(openalexR.mailto = openalex_email)

# Get today's date and the date one year ago
to_date <- Sys.getenv("to_publication_date", Sys.Date())
from_date <- as.Date(to_date) - 365

# Read journal ISSNs
initial_journals <- read_csv("initial_journals.csv")
issns <- initial_journals$issn

# Fetch data from OpenAlex
min_wage_papers_df <- oa_fetch(
  entity = "works",
  search = "\"minimum wage\"",
  from_publication_date = from_date,
  to_publication_date = to_date,
  `primary_location.source.issn` = issns,
  output = "dataframe"
)

# Process the data
if (!is.null(min_wage_papers_df) && nrow(min_wage_papers_df) > 0) {

  processed_df <- min_wage_papers_df %>%
    # Filter out papers with future publication dates
    filter(publication_date <= Sys.Date()) %>%
    mutate(
      authors = map_chr(authorships, ~paste(.x$display_name, collapse = "; "))
    )

  # Add journal column if it doesn't exist
  if (!"source_display_name" %in% names(processed_df)) {
    processed_df$journal <- NA_character_
  } else {
    processed_df <- processed_df %>%
      rename(journal = source_display_name)
  }

  # Rename id to openalex_id
  processed_df <- processed_df %>%
    rename(openalex_id = id)

  # Finalize the dataframe
  papers_df <- processed_df %>%
    mutate(abstract = NA_character_) %>% # Abstract is inverted index
    select(
      openalex_id,
      title,
      authors,
      publication_date,
      abstract,
      journal,
      doi
    )

  # Read existing data
  if (file.exists("min_wage_papers.csv")) {
    existing_papers <- read_csv("min_wage_papers.csv", show_col_types = FALSE) %>%
      mutate(
        openalex_id = as.character(openalex_id),
        publication_date = as.Date(publication_date, format = "%Y-%m-%d", na.rm = TRUE),
        first_retrieved_date = as.POSIXct(first_retrieved_date, na.rm = TRUE),
        last_updated_date = as.POSIXct(last_updated_date, na.rm = TRUE),
        abstract = as.character(abstract)
      )
  } else {
    existing_papers <- tibble()
  }

  # Get current datetime
  current_datetime <- Sys.time()

  if (nrow(existing_papers) > 0) {
    # 1. New papers: in new fetch but not in existing CSV
    new_papers <- papers_df %>%
      anti_join(existing_papers, by = "openalex_id") %>%
      mutate(
        first_retrieved_date = current_datetime,
        last_updated_date = current_datetime,
        status = "new"
      )

    # 2. Old papers: in existing CSV but not in new fetch
    old_papers <- existing_papers %>%
      anti_join(papers_df, by = "openalex_id") %>%
      mutate(status = "old")

    # 3. Common papers: in both new fetch and existing CSV. Need to check for actual updates.
    common_ids <- intersect(papers_df$openalex_id, existing_papers$openalex_id)

    if (length(common_ids) > 0) {
        # Get the newly fetched versions of common papers
        common_new <- papers_df %>%
          filter(openalex_id %in% common_ids)

        # Get the old versions of common papers
        common_old <- existing_papers %>%
          filter(openalex_id %in% common_ids)

        # For comparison, select only the columns present in the new fetch
        common_old_comparable <- common_old %>%
          select(any_of(names(common_new)))

        # Use anti_join to find the IDs of papers where data has changed
        updated_ids <- anti_join(
            common_new %>% arrange(openalex_id),
            common_old_comparable %>% arrange(openalex_id)
          ) %>%
          pull(openalex_id)

        # 3a. Papers that were actually updated
        updated_papers <- common_new %>%
          filter(openalex_id %in% updated_ids) %>%
          # Re-attach the original first_retrieved_date
          inner_join(common_old %>% select(openalex_id, first_retrieved_date), by = "openalex_id") %>%
          mutate(
            last_updated_date = current_datetime,
            status = "updated"
          )

        # 3b. Papers that were re-fetched but had no changes
        unchanged_papers <- common_old %>%
          filter(!openalex_id %in% updated_ids) %>%
          mutate(status = "old") # Keep status as old

        # Combine all the pieces
        combined_papers <- bind_rows(new_papers, old_papers, updated_papers, unchanged_papers)
    } else {
        # No common papers, just combine new and old
        combined_papers <- bind_rows(new_papers, old_papers)
    }

  } else {
    # This is the case for the very first run
    combined_papers <- papers_df %>%
      mutate(
        first_retrieved_date = current_datetime,
        last_updated_date = current_datetime,
        status = "new"
      )
  }

  # Sort the data
  combined_papers <- combined_papers %>%
    mutate(status = factor(status, levels = c("new", "updated", "old"))) %>%
    arrange(status, desc(publication_date))

  # Write to CSV
  write_csv(combined_papers, "min_wage_papers.csv")
} else {
  # Create an empty CSV if no papers are found
  tibble(
    openalex_id = character(),
    title = character(),
    authors = character(),
    publication_date = character(),
    abstract = character(),
    journal = character(),
    doi = character(),
    first_retrieved_date = character(),
    last_updated_date = character(),
    status = character()
  ) %>%
    write_csv("min_wage_papers.csv")
}
