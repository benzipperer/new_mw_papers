library(openalexR)
library(dplyr)
library(readr)
library(purrr)
library(tidyr)
library(lubridate)
library(stringr)
library(rvest)
library(httr)

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
    filter(first_retrieved_date >= Sys.Date() - 365) |>
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

    # Papers that were re-fetched but had no changes - preserve their status
    unchanged_papers = common_old |>
      filter(!openalex_id %in% updated_ids)

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

scrape_iza_paper = function(paper_url) {
  # Add delay to be polite to the server
  Sys.sleep(1)

  tryCatch(
    {
      page = read_html(paper_url)

      # Extract paper number from URL or page
      paper_id = str_extract(paper_url, "dp/(\\d+)/", group = 1)

      # Extract title - it's in h2 or div.title, includes paper number
      title_raw = page |>
        html_element("h2") |>
        html_text2()

      # Remove "IZA DP No. XXXXX: " prefix from title
      title = str_replace(title_raw, "^IZA DP No\\.\\s+\\d+:\\s*", "")

      # Extract authors - they're in a div.authors element
      authors = page |>
        html_element("div.authors") |>
        html_text2() |>
        str_replace_all(",", ";") # Convert commas to semicolons for consistency

      # Extract publication date - look for text like "October 2025" or "IZA DP No. 18234"
      # The date is typically in a span or div near the top
      date_text = page |>
        html_elements("p") |>
        html_text2() |>
        str_subset(
          "(January|February|March|April|May|June|July|August|September|October|November|December)\\s+\\d{4}"
        ) |>
        head(1)

      # Parse the date - extract month and year
      if (length(date_text) > 0) {
        date_parsed = str_extract(
          date_text,
          "(January|February|March|April|May|June|July|August|September|October|November|December)\\s+\\d{4}"
        )
        publication_date = parse_date_time(date_parsed, orders = "BY")
      } else {
        publication_date = NA
      }

      # Extract abstract - it's typically the second paragraph
      all_paragraphs = page |>
        html_elements("p") |>
        html_text2()

      # Filter for content paragraphs (usually starts with capital, has good length)
      content_paragraphs = all_paragraphs[nchar(all_paragraphs) > 100]

      # The abstract is usually the first substantial paragraph
      if (length(content_paragraphs) > 0) {
        abstract = content_paragraphs[1] |>
          str_squish()
      } else {
        abstract = NA_character_
      }

      tibble(
        openalex_id = paste0("iza", paper_id),
        title = title,
        authors = authors,
        publication_date = as.Date(publication_date),
        abstract = abstract,
        journal = "IZA Discussion Paper",
        doi = paper_url
      )
    },
    error = function(e) {
      message(paste("Error scraping", paper_url, ":", e$message))
      NULL
    }
  )
}

iza_fetch = function(
  from_publication_date,
  to_publication_date,
  search_query
) {
  # Browse all IZA discussion papers without search filter
  # Then filter by search query afterwards (like nber_fetch)
  base_url = "https://www.iza.org/publications/dp"

  # Get paper links from multiple pages
  # Using limit=100 and page-based pagination for most recent 200 papers
  all_paper_links = c()

  # Fetch 2 pages (100 papers per page = 200 papers total)
  for (page_num in 1:2) {
    search_url = paste0(base_url, "?limit=100&page=", page_num)

    message(paste("Fetching IZA papers page", page_num, "..."))

    tryCatch(
      {
        page = read_html(search_url)

        # Extract all paper links
        paper_links = page |>
          html_elements("a[href*='/publications/dp/']") |>
          html_attr("href") |>
          str_subset("/publications/dp/\\d+/") |>
          unique()

        if (length(paper_links) == 0) {
          message("No more papers found, stopping pagination.")
          break
        }

        # Convert relative URLs to absolute (only if they start with /)
        paper_links = ifelse(
          str_starts(paper_links, "/"),
          paste0("https://www.iza.org", paper_links),
          paper_links
        )
        all_paper_links = c(all_paper_links, paper_links)

        # Be polite - wait between page requests
        Sys.sleep(1)
      },
      error = function(e) {
        message(paste("Error fetching page", page_num, ":", e$message))
        break
      }
    )
  }

  # Remove duplicates
  all_paper_links = unique(all_paper_links)

  message(paste(
    "Found",
    length(all_paper_links),
    "total papers. Scraping details..."
  ))

  # Scrape each paper with early stopping and progress meter
  papers_list = list()
  consecutive_old_papers = 0
  from_date = ymd(from_publication_date)

  for (i in seq_along(all_paper_links)) {
    # Progress indicator
    if (i %% 10 == 0) {
      message(paste("Progress:", i, "/", length(all_paper_links), "papers"))
    }

    paper = scrape_iza_paper(all_paper_links[i])

    if (!is.null(paper)) {
      papers_list[[i]] = paper

      # Check if paper is before our date range
      if (
        !is.na(paper$publication_date) && paper$publication_date < from_date
      ) {
        consecutive_old_papers = consecutive_old_papers + 1

        # Stop if we've found 5 consecutive papers before the date range
        if (consecutive_old_papers >= 5) {
          message(paste(
            "Found 5 consecutive papers before",
            from_publication_date,
            "- stopping at paper",
            i,
            "of",
            length(all_paper_links)
          ))
          break
        }
      } else {
        # Reset counter if we find a paper in range
        consecutive_old_papers = 0
      }
    }
  }

  # Combine and filter by date range
  papers = papers_list |>
    bind_rows() |>
    filter(
      !is.na(publication_date),
      publication_date >= ymd(from_publication_date),
      publication_date <= ymd(to_publication_date)
    )

  message(paste("After date filtering:", nrow(papers), "papers"))

  # Apply search query filter using str_detect (like nber_fetch)
  if (!is.null(search_query) && search_query != "") {
    papers = papers |>
      mutate(
        abstract_match = str_detect(
          str_to_lower(abstract),
          str_to_lower(search_query)
        ),
        title_match = str_detect(
          str_to_lower(title),
          str_to_lower(search_query)
        )
      ) |>
      filter(abstract_match | title_match) |>
      select(-abstract_match, -title_match)
  }

  message(paste("Retrieved", nrow(papers), "IZA papers matching criteria"))

  papers
}

download_nber = function(name) {
  base_url = "https://data.nber.org/nber_paper_chapter_metadata/tsv/"
  file_name = paste0(name, ".tsv")
  url = paste0(base_url, file_name)
  # temp = tempfile()

  # download.file(url, temp)

  # deal with inconsistent quotes depending on file
  quote_option = "\""
  if (name == "ref") {
    quote_option = rawToChar(as.raw(0xAC))
  }

  data = read_delim(
    url,
    delim = "\t",
    quote = quote_option
  )

  # unlink(temp)

  data |>
    filter(str_starts(paper, "w"))
}


nber_fetch = function(
  from_publication_date,
  to_publication_date,
  search_query
) {
  ref = download_nber("ref")
  abs = download_nber("abs")
  jel = download_nber("jel") |>
    summarize(jel_codes = paste(jel, collapse = ","), .by = paper)

  data = ref |>
    full_join(abs, by = "paper") |>
    full_join(jel, by = "paper") |>
    mutate(
      authors = str_replace_all(author, ",", ";"),
      journal = "NBER Working Paper",
      doi = paste0("https://nber.org/papers/", paper),
      publication_date = issue_date,
      # deal with openalex vs NBER ids at some point
      # for now this is fine
      openalex_id = paper,
      abstract_match = str_detect(str_to_lower(abstract), nber_search_query),
      title_match = str_detect(str_to_lower(title), nber_search_query),
      # jel_match = str_detect(jel_codes, "J")
      jel_match = 1
    ) |>
    filter(
      publication_date >= ymd(from_publication_date),
      publication_date <= ymd(to_publication_date),
      jel_match == 1,
      abstract_match == 1 | title_match == 1
    ) |>
    select(
      openalex_id,
      authors,
      publication_date,
      title,
      journal,
      doi,
      abstract,
      jel_codes
    )

  data
}

# Set email for polite API access
openalex_email = Sys.getenv("openalexR.mailto", "agent@example.com")
options(openalexR.mailto = openalex_email)

# Get today's date and the date one year ago
oa_to_date = Sys.Date()
oa_from_date = as.Date(oa_to_date) - 365

# Read journal ISSNs
initial_journals = read_csv("initial_journals.csv")
issns = initial_journals$issn

oa_mw_query = '"minimum wage" OR "minimum wages" OR "minimum wage\'s"'
oa_lw_query = '"living wage" OR "living wages" OR "living wage\'s"'
oa_tw_query = '"tipped wage" OR "tipped wages" OR "tipped wage\'s"'

oa_search_query = paste(oa_mw_query, oa_lw_query, oa_tw_query, sep = " OR ")

# Fetch data from OpenAlex
papers_from_oa = oa_fetch(
  entity = "works",
  search = oa_search_query,
  from_publication_date = oa_from_date,
  to_publication_date = oa_to_date,
  primary_location.source.issn = issns,
  output = "dataframe"
) |>
  clean_oa_papers()

# nber_search_query = "minimum wage|living wage|tipped_wage"
# nber_to_date = Sys.Date()
# nber_from_date = as.Date(nber_to_date) - 365

# papers_from_nber = nber_fetch(
#   nber_from_date,
#   nber_to_date,
#   nber_search_query
# )

# Fetch papers from IZA
# Use regex pattern for filtering (like NBER)
# will only search the last two months
iza_search_query = "minimum wage|living wage|tipped wage"
iza_to_date = Sys.Date()
iza_from_date = as.Date(iza_to_date) - months(2)
papers_from_iza = iza_fetch(
  iza_from_date,
  iza_to_date,
  iza_search_query
)

all_papers = papers_from_oa |>
  #bind_rows(papers_from_nber) |>
  bind_rows(papers_from_iza) |>
  # remove false positives: Issue Information
  filter(str_to_lower(title) != "issue information")

# Existing data
existing_papers = NULL
if (file.exists("min_wage_papers.csv")) {
  existing_papers = read_csv("min_wage_papers.csv", show_col_types = FALSE)
}

combined_papers = update_papers(new = all_papers, old = existing_papers)

combined_papers |>
  write_csv("min_wage_papers.csv")

# Read list of already-emailed papers
emailed_papers = NULL
if (file.exists("emailed_papers.csv")) {
  emailed_papers = read_csv("emailed_papers.csv", show_col_types = FALSE)
}

# Find papers that are new AND haven't been emailed yet
combined_papers |>
  anti_join(emailed_papers, by = "openalex_id") |>
  write_csv("min_wage_papers_to_email.csv")
