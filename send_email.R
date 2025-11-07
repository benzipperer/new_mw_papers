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

# Get today's date for email subject
week_end_date <- format(Sys.Date(), "%B %d, %Y")

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
        <div class="metadata">
          <div class="journal"><a href="{doi}">{journal}</a></div>
          <div class="date">{publication_date}</div>
        </div>
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
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <style>
    * {{ margin: 0; padding: 0; box-sizing: border-box; }}
    body {{
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Oxygen", "Ubuntu", "Cantarell", sans-serif;
      line-height: 1.6;
      color: #24292e;
      background-color: #f8f9fa;
      padding: 20px;
    }}
    .container {{
      max-width: 800px;
      margin: 0 auto;
      background-color: #ffffff;
      border: 1px solid #e1e4e8;
      border-radius: 8px;
      box-shadow: 0 2px 8px rgba(0, 0, 0, 0.05);
      overflow: hidden;
    }}
    .header {{
      background-color: #f6f8fa;
      padding: 24px 32px;
      border-bottom: 2px solid #e1e4e8;
    }}
    .header h2 {{
      color: #24292e;
      font-size: 24px;
      font-weight: 600;
      margin-bottom: 8px;
    }}
    .intro {{
      padding: 24px 32px;
      font-size: 15px;
      color: #586069;
      border-bottom: 1px solid #e1e4e8;
    }}
    .intro a {{
      color: #0366d6;
      text-decoration: none;
      font-weight: 500;
    }}
    .intro a:hover {{
      color: #0256b9;
      text-decoration: underline;
    }}
    .count {{
      color: #24292e;
      font-weight: 600;
    }}
    .papers {{
      padding: 16px 32px 32px 32px;
    }}
    .paper {{
      margin-bottom: 24px;
      padding: 20px;
      background-color: #fafbfc;
      border: 1px solid #e1e4e8;
      border-radius: 6px;
      transition: box-shadow 0.15s ease;
    }}
    .paper:hover {{
      box-shadow: 0 2px 8px rgba(0, 0, 0, 0.1);
    }}
    .paper:last-child {{
      margin-bottom: 0;
    }}
    .authors {{
      color: #586069;
      font-size: 14px;
      margin-bottom: 8px;
      font-weight: 500;
    }}
    .title {{
      font-weight: 600;
      font-size: 16px;
      margin: 8px 0 12px 0;
      color: #24292e;
      line-height: 1.5;
    }}
    .metadata {{
      display: flex;
      flex-wrap: wrap;
      gap: 16px;
      font-size: 14px;
      margin-top: 8px;
    }}
    .date {{
      color: #586069;
    }}
    .date::before {{
      content: "📅 ";
      margin-right: 4px;
    }}
    .journal {{
      color: #0366d6;
      margin-right: 16px;
    }}
    .journal::before {{
      content: "📄 ";
      margin-right: 4px;
    }}
    .journal a {{
      color: #0366d6;
      text-decoration: none;
      font-weight: 500;
      transition: color 0.15s ease;
    }}
    .journal a:hover {{
      color: #0256b9;
      text-decoration: underline;
    }}
    .footer {{
      padding: 16px 32px;
      background-color: #f6f8fa;
      border-top: 1px solid #e1e4e8;
      font-size: 13px;
      color: #586069;
      text-align: center;
    }}

    /* Mobile responsive */
    @media only screen and (max-width: 600px) {{
      body {{ padding: 10px; }}
      .header, .intro, .papers, .footer {{ padding: 16px 20px; }}
      .paper {{ padding: 16px; }}
      .metadata {{ flex-direction: column; gap: 8px; }}
    }}
  </style>
</head>
<body>
  <div class="container">
    <div class="header">
      <h2>New Minimum Wage Papers Detected</h2>
    </div>
    <div class="intro">
      <p>The following <span class="count">{paper_count} new {paper_word}</span> {have_word} been added to the
      <a href="https://benzipperer.github.io/new_mw_papers/">Recent Minimum Wage Papers</a> list:</p>
    </div>
    <div class="papers">
      {paper_html}
    </div>
    <div class="footer">
      Automated notification from the Minimum Wage Papers tracking system
    </div>
  </div>
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

stop(print(envelope() |> to(email_bcc)))

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
        "New minimum wage papers for the week ending {week_end_date}"
      )) %>%
      html(html_body)

    # Add BCC if specified
    if (email_bcc != "") {
      email <- email %>% bcc(email_bcc)
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
