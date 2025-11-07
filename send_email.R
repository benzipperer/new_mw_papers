library(readr)
library(dplyr)
library(emayili)
library(glue)

# Read the CSV file for papers to email
if (!file.exists('min_wage_papers_to_email.csv')) {
  cat("No min_wage_papers_to_email.csv file found.\n")
  quit(status = 0)
}

papers <- read_csv('min_wage_papers_to_email.csv', show_col_types = FALSE) |>
  arrange(desc(publication_date))

# Check if there are any new papers
if (nrow(papers) == 0) {
  cat("No new papers found. Skipping email notification.\n")
  quit(status = 0)
}

# Determine singular/plural forms
paper_count <- nrow(papers)
paper_word <- if (paper_count == 1) "paper" else "papers"
have_word <- if (paper_count == 1) "has" else "have"

cat(glue("Found {paper_count} new {paper_word}. Preparing email...\n"))

# Create HTML for each paper
paper_html <- papers %>%
  mutate(
    # Escape HTML special characters
    title = gsub("&", "&amp;", title),
    title = gsub("<", "&lt;", title),
    title = gsub(">", "&gt;", title),
    title = gsub('"', "&quot;", title),
    authors = gsub("&", "&amp;", authors),
    authors = gsub("<", "&lt;", authors),
    authors = gsub(">", "&gt;", authors),
    authors = gsub('"', "&quot;", authors),
    journal = gsub("&", "&amp;", journal),
    journal = gsub("<", "&lt;", journal),
    journal = gsub(">", "&gt;", journal),
    journal = gsub('"', "&quot;", journal),
    # Create HTML for each paper
    html = glue(
      '
    <div class="paper">
      <div class="authors">{authors}</div>
      <div class="title">{title}</div>
      <div class="date">Publication Date: {publication_date}</div>
      <div class="journal"><a href="{doi}">{journal}</a></div>
    </div>
    '
    )
  ) %>%
  pull(html) %>%
  paste(collapse = "\n")

# Create full HTML email body
html_body <- glue(
  '
<!DOCTYPE html>
<html>
<head>
  <style>
    body {{ font-family: Arial, sans-serif; line-height: 1.6; color: #333; max-width: 800px; margin: 0 auto; padding: 20px; }}
    h2 {{ color: #2c3e50; border-bottom: 2px solid #3498db; padding-bottom: 10px; }}
    .paper {{ margin-bottom: 25px; padding: 15px; background-color: #f8f9fa; border-left: 4px solid #3498db; }}
    .authors {{ color: #7f8c8d; font-style: italic; margin-bottom: 5px; }}
    .date {{ color: #95a5a6; font-size: 0.9em; margin-bottom: 5px; }}
    .title {{ font-weight: bold; font-size: 1.1em; margin: 8px 0; color: #2c3e50; }}
    .journal {{ color: #2980b9; margin-top: 5px; }}
    .journal a {{ color: #2980b9; text-decoration: none; }}
    .journal a:hover {{ text-decoration: underline; }}
    .count {{ color: #27ae60; font-weight: bold; }}
  </style>
</head>
<body>
  <h2>New Minimum Wage Papers Detected</h2>
  <p>The following <span class="count">{paper_count} new {paper_word}</span> {have_word} been added to the list of
  <a href="https://benzipperer.github.io/new_mw_papers/">Recent Minimum Wage Papers</a>:</p>
  {paper_html}
</body>
</html>
'
)

# Get email configuration from environment variables
email_from <- Sys.getenv("EMAIL_FROM")
email_to <- Sys.getenv("EMAIL_TO")
email_bcc <- Sys.getenv("EMAIL_BCC") # Optional BCC recipients (comma-separated)
smtp_server <- Sys.getenv("SMTP_SERVER")
smtp_port <- as.integer(Sys.getenv("SMTP_PORT"))
smtp_username <- Sys.getenv("SMTP_USERNAME")
smtp_password <- Sys.getenv("SMTP_PASSWORD")

# Validate required environment variables
if (
  smtp_server == "" ||
    smtp_username == "" ||
    smtp_password == "" ||
    email_from == "" ||
    email_to == ""
) {
  stop("Missing required environment variables for email configuration")
}
message("This is the email from", email_from)

# Send email using emayili
tryCatch(
  {
    # Create SMTP server connection
    smtp <- server(
      host = smtp_server,
      port = smtp_port,
      username = smtp_username,
      password = smtp_password
    )

    # Create email
    email <- envelope() %>%
      from(email_from) %>%
      to(email_to) %>%
      subject(glue(
        "New Minimum Wage Papers: {paper_count} {paper_word} added"
      )) %>%
      html(html_body)

    # Add BCC if specified
    if (email_bcc != "") {
      email <- email %>% bcc(email_bcc)
      message("BCC is present")
    } else {
      message(email_to)
      message(email_bcc)
      stop("No BCC present")
    }

    # Send email
    smtp(email, verbose = TRUE)

    cat("Email sent successfully.\n")
  },
  error = function(e) {
    cat("Error sending email:", conditionMessage(e), "\n")
    quit(status = 1)
  }
)

# Update emailed papers list
emailed_papers <- data.frame(openalex_id = character(0))
if (file.exists('emailed_papers.csv')) {
  emailed_papers <- read_csv('emailed_papers.csv', show_col_types = FALSE)
}

# Add new paper IDs
updated_emailed <- bind_rows(
  emailed_papers,
  papers %>% select(openalex_id)
) %>%
  distinct(openalex_id) %>%
  arrange(openalex_id)

# Write updated list back to file
write_csv(updated_emailed, 'emailed_papers.csv')

cat(glue("Updated emailed_papers.csv with {nrow(papers)} new paper(s).\n"))
