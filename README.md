# Moved

## Super pointless

Creates an  AWS Lambda Function and DynamoDB Table

A "last page" exists at the location `/hello`

Lambda serves the page via an API G/W (full HTML is embedded in the Lambda)

When the "last page" is visited, the location of the "last page" is moved to a new `/{uuid-v4}`, this is stored in the DB.

The previous "last page" is now a "link page"

A linked list of "link pages" grows, with the "last page" moving each time it is found

DynamoDB stores the trail of movements and visits to each link page.


## Installation

Grab the repo
```
terraform plan
terraform apply
```
## Lambda function code

Look in /function
