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

# Get today's date and the date one month ago
to_date <- Sys.Date()
from_date <- to_date - 30

# Fetch data from OpenAlex
min_wage_papers_df <- oa_fetch(
  entity = "works",
  search = "\"minimum wage\"",
  from_publication_date = from_date,
  to_publication_date = to_date,
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

  # Finalize the dataframe
  papers_df <- processed_df %>%
    mutate(abstract = NA_character_) %>% # Abstract is inverted index
    select(
      title,
      authors,
      publication_date,
      abstract,
      journal,
      doi
    )

  # Write to CSV
  write_csv(papers_df, "min_wage_papers.csv")
} else {
  # Create an empty CSV if no papers are found
  tibble(
    title = character(),
    authors = character(),
    publication_date = character(),
    abstract = character(),
    journal = character(),
    doi = character()
  ) %>%
    write_csv("min_wage_papers.csv")
}
