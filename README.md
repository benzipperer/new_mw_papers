# Minimum Wage Papers Tracker

This project automatically collects bibliographic information for recent minimum wage papers from the OpenAlex API and displays them on a GitHub Pages website.

## How it works

A GitHub Actions workflow runs daily, executing an R script (`min_wage_papers.R`) that:
1.  Fetches data for papers matching the keyword "minimum wage" from the last month using the `openalexR` package.
2.  Extracts the title, authors, publication date, abstract, journal name, and DOI.
3.  Saves the data to a CSV file (`min_wage_papers.csv`).

The workflow then renders a Quarto document (`index.qmd`) to an HTML file, which is published as a GitHub Pages site. The site displays the contents of the CSV file in an interactive table using the `reactable` package.

## Setup

### Required GitHub Secrets

To run this project, you need to configure the following secrets in your repository's settings (Settings > Secrets and variables > Actions):

#### OpenAlex API Access
- **OPENALEX_EMAIL**: Your email address for polite access to the OpenAlex API

#### Email Notifications
The workflow will send email notifications when new papers are detected. Configure these SMTP settings:

- **SMTP_SERVER**: Your SMTP server address (e.g., `smtp.gmail.com`)
- **SMTP_PORT**: Your SMTP server port (e.g., `587` for TLS, `465` for SSL)
- **SMTP_USERNAME**: Your SMTP username (usually your email address)
- **SMTP_PASSWORD**: Your SMTP password or app-specific password
- **EMAIL_TO**: The recipient email address for notifications
- **EMAIL_FROM**: The sender email address (usually the same as SMTP_USERNAME)

**Note for Gmail users**: You'll need to use an [App Password](https://support.google.com/accounts/answer/185833) instead of your regular password.

### Email Notification Features

The workflow automatically sends HTML-formatted email notifications when new papers are added to the database. Each notification includes:
- Authors (semicolon-separated)
- Publication date
- Paper title
- Journal name (hyperlinked to the article DOI)

Emails are only sent when the `min_wage_papers_new.csv` file contains new papers (non-empty after the header row).
