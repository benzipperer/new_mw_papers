library(openalexR)
library(dplyr)
library(readr)
library(purrr)
library(tidyr)
library(lubridate)

update_papers = function(new, old) {
  if (is.null(new) & is.null(old)) {
    stop("PROBLEM: No data exists.")
  } else if (is.null(new) & !is.null(old)) {
    output = old
  } else if (!is.null(new) & is.null(old)) {
    output = new |>
      mutate(
        status = "new",
        first_retrieved_date = Sys.Date(),
        last_updated_date = Sys.Date()
      )
  } else {
    output = combine_papers(new, old)
  }

  output |>
    select(
      openalex_id,
      title,
      authors,
      publication_date,
      abstract,
      journal,
      doi,
      status,
      first_retrieved_date,
      last_updated_date
    ) |>
    arrange(desc(first_retrieved_date))
}

combine_papers = function(new, old) {
  # New papers: in new fetch but not in existing CSV
  new_papers = new |>
    anti_join(old, by = "openalex_id") |>
    mutate(
      first_retrieved_date = Sys.Date(),
      last_updated_date = Sys.Date(),
      status = "new"
    )

  # Old papers: in existing CSV but not in new fetch
  old_papers = old |>
    anti_join(new, by = "openalex_id") |>
    mutate(status = "old")

  # Common papers that may or may not have been updated
  common_papers = create_common_papers(new, old)

  bind_rows(
    new_papers,
    old_papers,
    common_papers
  )
}

create_common_papers = function(new, old) {
  # Common papers: in both new fetch and existing CSV. Need to check for actual updates.
  common_ids <- intersect(
    new$openalex_id,
    old$openalex_id
  )

  if (length(common_ids) == 0) {
    common_papers = NULL
  } else {
    # Get the newly fetched versions of common papers
    common_new = new |>
      filter(openalex_id %in% common_ids)

    # Get the old versions of common papers
    common_old = old |>
      filter(openalex_id %in% common_ids)

    # For comparison, select only the columns present in the new fetch
    common_old_comparable = common_old |>
      select(any_of(names(common_new)))

    # IDs of actually updated papers (where any data has changed)
    updated_ids = anti_join(
      common_new |> arrange(openalex_id),
      common_old_comparable |> arrange(openalex_id)
    ) |>
      pull(openalex_id)

    # Papers that were actually updated
    updated_papers = common_new |>
      filter(openalex_id %in% updated_ids) |>
      # Re-attach the original first_retrieved_date
      inner_join(
        common_old |> select(openalex_id, first_retrieved_date),
        by = "openalex_id"
      ) |>
      mutate(
        last_updated_date = Sys.time(),
        status = "updated"
      )

    # Papers that were re-fetched but had no changes
    unchanged_papers = common_old |>
      filter(!openalex_id %in% updated_ids) |>
      mutate(status = "old")

    common_papers = bind_rows(updated_papers, unchanged_papers)
  }

  common_papers
}

clean_oa_papers = function(data) {
  if (is.null(data)) {
    NULL
  } else {
    data |>
      mutate(
        authors = map_chr(
          authorships,
          ~ paste(.x$display_name, collapse = "; ")
        )
      ) |>
      select(
        openalex_id = id,
        authors,
        publication_date,
        title,
        journal = source_display_name,
        doi,
        abstract
      )
  }
}


# Set email for polite API access
openalex_email = Sys.getenv("openalexR.mailto", "agent@example.com")
options(openalexR.mailto = openalex_email)

# Get today's date and the date one year ago
to_date = Sys.getenv("to_publication_date", Sys.Date())
from_date = as.Date(to_date) - 365

# Read journal ISSNs
initial_journals = read_csv("initial_journals.csv")
issns = initial_journals$issn

# Fetch data from OpenAlex
papers_from_oa = oa_fetch(
  entity = "works",
  search = "\"minimum wage\"",
  #search = "\"blah tiddly blah\"",
  from_publication_date = from_date,
  to_publication_date = to_date,
  primary_location.source.issn = issns,
  output = "dataframe"
) |>
  clean_oa_papers()

# Existing data
existing_papers = NULL
if (file.exists("min_wage_papers.csv")) {
  existing_papers = read_csv("min_wage_papers.csv", show_col_types = FALSE)
}

combined_papers = update_papers(new = papers_from_oa, old = existing_papers)

write_csv(combined_papers, "min_wage_papers.csv")
