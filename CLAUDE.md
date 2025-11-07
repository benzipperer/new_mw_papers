# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is an automated minimum wage research paper tracking system that:
1. Fetches papers from OpenAlex API, NBER, and IZA matching minimum wage keywords
2. Maintains a database of papers with status tracking (new/old/updated)
3. Sends email notifications for newly discovered papers
4. Publishes an interactive HTML table to GitHub Pages

The system runs via three separate GitHub Actions workflows that operate on different schedules.

## Key Files

### R Scripts
- `min_wage_papers.R` - Main data fetching and processing script. Queries OpenAlex API and NBER, merges with existing data, tracks paper status (new/old/updated), and generates CSV outputs.
- `send_email.R` - Email notification system using the `blastula` package. Sends HTML-formatted emails for new papers.
- `index.qmd` - Quarto document that renders the website, displaying papers in an interactive `reactable` table.

### Data Files
- `min_wage_papers.csv` - Main database of all papers (last 365 days)
- `min_wage_papers_to_email.csv` - Papers that need to be emailed (status="new" AND not yet emailed)
- `emailed_papers.csv` - Tracking file to prevent duplicate email notifications
- `initial_journals.csv` - List of journal ISSNs to query in OpenAlex

### GitHub Actions Workflows
- `.github/workflows/update_data.yml` - Runs daily at 5:30 AM UTC (`cron: '30 5 * * *'`). Executes `min_wage_papers.R` and commits updated CSVs. Manual trigger via `workflow_dispatch`.
- `.github/workflows/send_email.yml` - Runs weekly on Fridays at 9:30 AM UTC (`cron: '30 9 * * 5'`). Executes `send_email.R` to notify about new papers and commits `emailed_papers.csv`. Manual trigger via `workflow_dispatch`.
- `.github/workflows/deploy_website.yml` - Triggers on push to main branch when `min_wage_papers.csv` or `index.qmd` changes. Renders Quarto site and deploys to GitHub Pages. Manual trigger via `workflow_dispatch`.

## Architecture

### Data Pipeline Flow
1. **Fetch** (update_data.yml): `min_wage_papers.R` queries APIs → updates `min_wage_papers.csv` and `min_wage_papers_to_email.csv`
2. **Notify** (send_email.yml): `send_email.R` reads `min_wage_papers_to_email.csv` → sends emails → updates `emailed_papers.csv`
3. **Publish** (deploy_website.yml): Quarto renders `index.qmd` using `min_wage_papers.csv` → deploys to GitHub Pages

### Paper Status Tracking
The system maintains three states in `min_wage_papers.R`:
- **new**: Paper appears in API fetch but not in existing CSV
- **old**: Paper exists in CSV but no longer appears in API fetch
- **updated**: Paper exists in both, but metadata has changed

Status tracking prevents duplicate emails by maintaining two separate tracking mechanisms:
1. Status field in `min_wage_papers.csv` (managed by `update_papers()` and `combine_papers()`)
2. Separate `emailed_papers.csv` tracking file (prevents re-emailing if paper status changes)

### Search Queries
- OpenAlex: Searches for "minimum wage", "living wage", "tipped wage" (with variations) in journals matching ISSNs from `initial_journals.csv`. Looks back 365 days.
- NBER: Downloads full metadata TSV files, filters by regex matching in title/abstract. Looks back 365 days.
- IZA: Scrapes IZA Discussion Papers website, filters by regex matching in title/abstract. Looks back 2 months only (shorter window to minimize scraping load).

## Development Commands

### Local Testing
```bash
# Run data update script (requires OPENALEX_EMAIL environment variable)
Rscript min_wage_papers.R

# Test email sending (requires SMTP environment variables)
Rscript send_email.R

# Render website locally
quarto render index.qmd

# Preview rendered site
quarto preview index.qmd
```

### Manual Workflow Triggers
All workflows support `workflow_dispatch` for manual triggering via GitHub Actions UI:
1. Navigate to Actions tab in GitHub repository
2. Select the workflow from the left sidebar
3. Click "Run workflow" button
4. Select branch and confirm

### Required Environment Variables
- `OPENALEX_EMAIL`: Email for OpenAlex API polite access
- `SMTP_SERVER`, `SMTP_PORT`, `SMTP_USERNAME`, `SMTP_PASSWORD`: Email sending credentials
- `EMAIL_FROM`, `EMAIL_TO`: Sender and recipient email addresses
- `PAT_GITHUB`: Personal access token for pushing commits from GitHub Actions

## R Package Dependencies

Dependencies are managed via GitHub Actions using `r-lib/actions/setup-r-dependencies@v2`, which reads from DESCRIPTION file (if present) or installs packages as needed.

### Core Data Processing (min_wage_papers.R)
- `openalexR`: OpenAlex API client
- `dplyr`, `tidyr`, `purrr`: Data manipulation
- `readr`: CSV reading/writing
- `lubridate`: Date handling
- `stringr`: String operations
- `rvest`: HTML web scraping (for IZA)
- `httr`: HTTP requests

### Email Notification (send_email.R)
- `readr`, `dplyr`: Data manipulation
- `blastula`: HTML email composition and SMTP sending
- `glue`: String interpolation for email templates

### Web Rendering (index.qmd)
- `readr`, `dplyr`: Data reading and manipulation
- `reactable`: Interactive HTML tables
- `htmltools`: HTML generation

## Important Implementation Details

### Data Retention
Papers are filtered to only include those with `first_retrieved_date >= Sys.Date() - 365`. This 365-day rolling window is applied in:
- `min_wage_papers.R`: Final output filtering in `update_papers()` function
- `index.qmd`: Display filtering when reading the CSV

### Non-OpenAlex ID Handling
NBER papers use their paper ID (e.g., "w12345") as `openalex_id`, and IZA papers use "iza" + paper ID (e.g., "iza12345"). This allows unified tracking across all data sources, but means `openalex_id` is not always an actual OpenAlex ID.

### Core Functions in min_wage_papers.R
- `update_papers(new, old)`: Main reconciliation function that handles null cases and calls `combine_papers()`
- `combine_papers(new, old)`: Identifies new, old, and common papers by comparing fetched data with existing CSV
- `create_common_papers(new, old)`: Detects which common papers have actually been updated by comparing metadata
- `clean_oa_papers(data)`: Transforms raw OpenAlex API response into standardized schema
- `nber_fetch()`: Downloads NBER metadata TSV files (ref, abs, jel) and joins them
- `iza_fetch()`: Web scraping implementation with polite delays and early stopping after 5 consecutive old papers
- `scrape_iza_paper(url)`: Individual paper scraper with error handling

### Email HTML Sanitization
The `send_email.R` script manually escapes HTML special characters (&, <, >, ") in title, authors, and journal fields to prevent rendering issues.

### Website Mobile Responsiveness
The reactable table uses custom HTML cells with `data-label` attributes for responsive mobile display (see `styles.css` for mobile-specific CSS).

### IZA Scraping Strategy
IZA papers are fetched via web scraping with:
- Pagination through 2 pages (100 papers per page = 200 papers max)
- Early stopping after 5 consecutive papers before date range (typically stops much earlier than 200 papers)
- 1-second delays between requests (polite scraping)
- Shorter lookback window (2 months vs 365 days for other sources) to minimize scraping load
- Individual paper scraping with error handling to gracefully skip problematic pages
