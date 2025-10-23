# Minimum Wage Papers Tracker

This project automatically collects bibliographic information for recent minimum wage papers from the OpenAlex API and displays them on a GitHub Pages website.

## How it works

A GitHub Actions workflow runs daily, executing an R script (`min_wage_papers.R`) that:
1.  Fetches data for papers matching the keyword "minimum wage" from the last month using the `openalexR` package.
2.  Extracts the title, authors, publication date, abstract, journal name, and DOI.
3.  Saves the data to a CSV file (`min_wage_papers.csv`).

The workflow then renders a Quarto document (`index.qmd`) to an HTML file, which is published as a GitHub Pages site. The site displays the contents of the CSV file in an interactive table using the `reactable` package.

## Setup

To run this project, you will need to set up an `OPENALEX_EMAIL` secret in your repository's settings. This is required for polite access to the OpenAlex API.
