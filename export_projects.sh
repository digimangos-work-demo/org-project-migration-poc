#!/bin/bash

# Initialize variables with default values
org_name=""
required_version="2.36.0"
export_path="export"

# Function to display script usage
show_usage() {
    echo "Usage: $0 -o <organization_name> [-p <export_path>]"
}

# Function to create the export folder if it doesn't exist
create_export_path() {
    if [ ! -d "${export_path}" ]; then
        mkdir -p "${export_path}"
        echo "Created export path: ${export_path}"
    else
        echo "Export path ${export_path} already exists. Please delete it or specify a new path."
        exit 1
    fi
}

# Function to list projects for a specified organization
export_projects() {
    local org=$1
    local export_path=$2

    # Execute gh project list and export the result
    gh project list --owner "${org}" --format json > "${export_path}/projects_list.json"
    echo "Exported project list for ${org} to ${export_path}/projects_list.json"
}

# Function to export project items by number
export_project_items() {
    local org=$1
    local export_path=$2
    local projects_file="${export_path}/projects_list.json"

    # Check if the projects_list.json file exists
    if [ ! -f "${projects_file}" ]; then
        echo "projects_list.json file not found at ${projects_file}. Please export projects first."
        exit 1
    fi

    # Iterate through project numbers and export items and fields
    projects=$(jq -r '.projects[].number' "${projects_file}")
    for project_number in ${projects}; do
        # Execute gh project item-list and export it
        gh project item-list "${project_number}" --owner "${org}" --format json > "${export_path}/project_${project_number}_items.json"
        echo "Exported project ${project_number} items to ${export_path}/project_${project_number}_items.json"

        # Execute gh project field-list and export it
        gh project field-list "${project_number}" --owner "${org}" --format json > "${export_path}/project_${project_number}_fields.json"
        echo "Exported project ${project_number} fields to ${export_path}/project_${project_number}_fields.json"
    done
}

# Parse command line options
while getopts "o:p:" opt; do
    case "$opt" in
        o)
            org_name="${OPTARG}"
            ;;
        p)
            export_path="${OPTARG}"
            ;;
        *)
            show_usage
            exit 1
            ;;
    esac
done

# Verify that organization name is provided
if [ -z "${org_name}" ]; then
    echo "Organization name is required."
    show_usage
    exit 1
fi

# Check if GitHub CLI is installed
if ! command -v gh &> /dev/null; then
    echo "GitHub CLI is not installed. Please install it."
    exit 1
fi

# Get the installed GitHub CLI version
installed_version=$(gh --version | awk '{print $3}')

# Function to compare version numbers
compare_versions() {
    local ver1=$1
    local ver2=$2
    if [[ "$ver1" == "$ver2" ]]; then
        return 0  # Versions are equal
    elif [[ $(printf "${ver1}\n${ver2}" | sort -V | tail -n 1) == "$ver2" ]]; then
        echo "Installed GitHub CLI version (${ver1}) is older than the required version (${ver2})."
        exit 1
    fi
}

# Compare versions
compare_versions "${installed_version}" "${required_version}"

# Create the export path if it doesn't exist
create_export_path

# List projects for the specified organization
export_projects "${org_name}" "${export_path}"

# Export project items if the organization and export path are provided
export_project_items "${org_name}" "${export_path}"
