#!/bin/bash

# Ensure you have authenticated with GitHub CLI using `gh auth login` before running this script.
# And added the required project scope using `gh auth refresh -s project`

# Initialize variables with default values
target_org=""
mapping_file="repository_mapping.txt"
projects_list_file="projects_list.json"
import_path="export"
ignore_mapping=false  # Flag to ignore mapping file
use_existing_copy_files=false  # Flag to use existing project copy JSON output files
specific_project=""
fields_to_ignore=("Title" "Assignees" "Labels" "Linked pull requests" "Reviewers" "Repository" "Milestone")

# GraphQL query to fetch project fields
project_fields_query=$(cat <<EOF
query (\$owner: String!, \$project_number: Int!, \$cursor: String) {
	organization(login: \$owner) {
		projectV2(number: \$project_number) {
			fields(first: 100, after: \$cursor) {
				pageInfo {
					hasNextPage
					endCursor
				}
				nodes {
					... on ProjectV2Field {
						__typename
						id
						name
						dataType
					}
					... on ProjectV2IterationField {
						__typename
						id
						name
						dataType
						configuration {
							iterations {
								id
								startDate
								title
								duration
							}
						}
					}
					... on ProjectV2SingleSelectField {
						__typename
						id
						name
						dataType
						options {
							id
							name
						}
					}
				}
			}
		}
	}
}
EOF
)

# Function to display script usage
show_usage() {
    echo "Usage: $0 -o <target_organization> [-m <repository_mapping_file>] [-p <projects_list_file>] [-i <import_path>] [-n] [-s <specific_project_number>]"
    echo "  -n: Ignore mapping file and use the same repository names"
    echo "  -s: Import a specific project by providing its number"
}

# Function to check if the provided import path exists
check_import_path() {
    local path="$1"
    [ ! -d "${path}" ] && echo "Import path '${path}' does not exist." && exit 1
}

# Function to check if a specific project copy output file exists
check_specific_project_file() {
    local project_number="$1"
    local output_file="${import_path}/project_${project_number}_copy_output.json"
    [ -f "${output_file}" ] && echo "Project copy output file for project ${project_number} already exists." && exit 1
}

# Function to check if any project copy JSON output files exist
check_project_copy_files() {
    if [ "$use_existing_copy_files" = true ]; then
        echo "Using existing project copy JSON output files if they already exist; otherwise, performing project copy."
        return
    elif [ -n "${specific_project}" ]; then
        check_specific_project_file "${specific_project}"
    elif [ -n "$(find "${import_path}" -maxdepth 1 -type f -name 'project_*_copy_output.json')" ]; then
        echo "Project copy JSON output files already exist in the import directory." && exit 1
    fi
}

# Function to check if mapping file is required
check_mapping_file() {
    if [ "$ignore_mapping" = false ]; then
        [ ! -f "${mapping_file}" ] && echo "Mapping file '${mapping_file}' is not present. Provide the mapping file or use '-n' to use the same repository names." && exit 1
    fi
}

# Function to convert the first character of a string to lowercase
first_char_to_lower() {
    input_string="$1"
    first_char="${input_string:0:1}"
    rest_of_string="${input_string:1}"
    lowercase_first_char=$(tr '[:upper:]' '[:lower:]' <<< "${first_char}")
    echo "${lowercase_first_char}${rest_of_string}"
}

# Function to validate that all referenced repositories are in the mapping file
validate_repositories() {
    local import_path="$1"
    local mapping_file="$2"

    referenced_repositories=$(find "${import_path}" -type f -name 'project_*_items.json' -exec jq -r '.items[].repository' {} \; | sort -u)
    mapped_repositories=$(cut -d ',' -f 1 "${mapping_file}" | sort -u)
    
    # Check if there are any unreferenced repositories
    unreferenced_repositories=$(comm -13 <(echo "${referenced_repositories}") <(echo "${mapped_repositories}"))
    
    if [ -n "${unreferenced_repositories}" ]; then
        echo "Error: Some repositories referenced in project_items.json files are not found in the mapping file:"
        echo "${unreferenced_repositories}"
        exit 1
    fi
}

# Function to copy a project
copy_project() {
    local project_number="$1"
    local source_org="$2"
    local title="$3"
    local output_file="${import_path}/project_${project_number}_copy_output.json"
    
    # Check if the output file already exists
    if [ -f "${output_file}" ]; then
        echo "Project copy output file for project ${project_number} already exists."
        return
    fi
    
    # Copy the project to the new organization and export the output
    echo "Copying project ${project_number} (${title}) from ${source_org} to ${target_org}..."
    
    gh project copy "${project_number}" --drafts --format json \
        --source-owner "${source_org}" --target-owner "${target_org}" --title "${title}" \
        > "${output_file}"
    
    # Check the exit status of the gh project copy command
    if [ $? -eq 0 ]; then
        echo "Project ${project_number} copied successfully."
    else
        echo "Failed to copy project ${project_number}. Check ${output_file} for details."
    fi
}

# Function to get project fields
export_project_fields() {
    local original_project_number="$1"
    local new_project_number=$(jq -r '.number' "${import_path}/project_${original_project_number}_copy_output.json")
    local output_file="${import_path}/project_${original_project_number}_copy_fields.json"
    
    # Check if the output file already exists
    if [ -f "${output_file}" ]; then
        echo "Project copy fields for new project: ${new_project_number} already exists."
        return
    fi
    
    gh api graphql --paginate -f query="${project_fields_query}" -f owner="${target_org}" -F project_number=${new_project_number} -q "[.data.organization.projectV2.fields.nodes[]]" > "${output_file}"
    echo "Exported project ${new_project_number} fields to ${output_file}"
    
    # Check the exit status of the gh project copy command
    if [ $? -eq 0 ]; then
        echo "Project ${original_project_number} (now ${new_project_number}) fields copied successfully."
    else
        echo "Failed to export fields for project ${original_project_number} (now ${new_project_number}). Check ${output_file} for details."
    fi
}

# Function to remap repositories based on the mapping file or use the original name
remap_repository() {
    local original_repo="$1"
    local map_file="$2"
    local remapped_repo
    
    if [ "$ignore_mapping" = true ]; then
        echo "${original_repo}"  # Use the original repository name
    else
        remapped_repo=$(grep "^${original_repo}," "${map_file}" | cut -d ',' -f 2)
        
        if [ -n "${remapped_repo}" ]; then
            echo "${remapped_repo}"
        else
            echo "${original_repo}"
        fi
    fi
}

# Function to extract project numbers and titles from projects_list.json
extract_project_info() {
    local import_path="$1"
    local projects_list_file="$2"
    jq -r '.projects[] | "\(.number)\t\(.title)\t\(.owner.login)"' "${import_path}/${projects_list_file}"
}

# Function to link old issues to new projects
link_old_issues() {
    local project_number="$1"
    local output_file="${import_path}/project_${project_number}_copy_output.json"
    local fields_file="${import_path}/project_${project_number}_copy_fields.json"
    local items_file="${import_path}/project_${project_number}_items.json"
    local fields=()

    while IFS=\= read -r value; do
        fields+=("${value}")
    done < <(jq -r '.[] | "\(.name)"' "${fields_file}")

    # Create a new array for the fields to include
    fields_to_include=()

    for ((i = 0; i < ${#fields[@]}; i++)); do
        if [[ ! " ${fields_to_ignore[@]} " =~ " ${fields[$i]} " ]]; then
            fields_to_include+=("${fields[$i]}")
        fi
    done

    # Check if the items file exists
    if [ -f "${items_file}" ]; then
        local new_project_number=$(jq -r '.number' "${output_file}")
        local new_project_id=$(jq -r '.id' "${output_file}")
        local items=$(jq -r '.items[] | "\(.content.url)"' "${items_file}")
        
        echo "Linking old issues from project ${project_number} to new project ${new_project_number} in ${targetOrg}..."
        
        while read -r issue_url; do
            local remapped_issue_url=$(remap_issue_url "${issue_url}")
            
            local add_result=$(gh project item-add "${new_project_number}" --owner "${target_org}" --url "${remapped_issue_url}" --format json)
            if [ $? -ne 0 ]; then
                echo "Failed to add item: ${remapped_issue_url}."
            fi

            local item_id=$(echo "${add_result}" | jq -r '.id')
            echo "Updating project metadata for item ${remapped_issue_url}"
            for ((i = 0; i < ${#fields_to_include[@]}; i++)); do
                local field=${fields_to_include[$i]}
                local attribueName=$(first_char_to_lower "${field}")
                local aresult=$(jq -r ".items[] | select(.content.url == \"${issue_url}\") | .\"${attribueName}\"" "${items_file}")
                
                if [ -n "${aresult}" ]; then
                  local field_id=$(jq -r ".[] | select(.name == \"${field}\") | .id" "${fields_file}")
                  local data_type=$(jq -r ".[] | select(.name == \"${field}\") | .dataType" "${fields_file}")

                  case "${data_type}" in
                    SINGLE_SELECT)
                      local ss=$(jq -r ".[] | select(.name == \"${field}\") | .options[] | select(.name == \"${aresult}\") | .id" "${fields_file}")
                      if [ -z "${ss}" ]; then
                        echo "Single select option not found: ${aresult}"
                      else
                        gh project item-edit --id "${item_id}" --field-id "${field_id}" --project-id "${new_project_id}" --single-select-option-id "${ss}"
                      fi
                      ;;
                    ITERATION)
                      local iteration_start_date=$(echo "${aresult}" | jq -r '.startDate')
                      local iteration_duration=$(echo "${aresult}" | jq -r '.duration')
                      local iteration_title=$(echo "${aresult}" | jq -r '.title')
                      local it=$(jq -r ".[] | select(.name == \"${field}\") | .configuration.iterations[] | select(.duration == ${iteration_duration} and .startDate == \"${iteration_start_date}\" and .title == \"${iteration_title}\") | .id" "${fields_file}")
                      if [ -z "${it}" ]; then
                        echo "Iteration not found: ${aresult}"
                      else
                        gh project item-edit --id "${item_id}" --field-id "${field_id}" --project-id "${new_project_id}" --iteration-id "${it}"
                      fi
                      ;;
                    NUMBER)
                      gh project item-edit --id "${item_id}" --field-id "${field_id}" --project-id "${new_project_id}" --number ${aresult}
                      ;;
                    DATE)
                      gh project item-edit --id "${item_id}" --field-id "${field_id}" --project-id "${new_project_id}" --date "${aresult}"
                      ;;
                    *)
                      gh project item-edit --id "${item_id}" --field-id "${field_id}" --project-id "${new_project_id}" --text "${aresult}"
                      ;;
                  esac
                fi
            done
        done <<< "${items}"
    else
      echo "Project items file not found at ${items_file}. Please export project items first."
    fi
}

# Function to remap the issue URL
remap_issue_url() {
    local issue_url="$1"
    local original_org=$(echo "${issue_url}" | awk -F'/' '{print $4}')
    local original_repo=$(echo "${issue_url}" | awk -F'/' '{print $5}')
    local new_org="${target_org}"
    local remapped_repo=$(remap_repository "${original_repo}" "${mapping_file}")
    echo "${issue_url}" | sed "s/${original_org}\/${original_repo}/${new_org}\/${remapped_repo}/"
}

# Parse command line options
while getopts "o:m:p:i:nes:" opt; do
    case "$opt" in
        o) target_org="${OPTARG}" ;;
        m) mapping_file="${OPTARG}" ;;
        p) projects_list_file="${OPTARG}" ;;
        i) import_path="${OPTARG}" ;;
        n) ignore_mapping=true ;;
        e) use_existing_copy_files=true ;;
        s) specific_project="${OPTARG}" ;;
        *) show_usage && exit 1 ;;
    esac
done

# Verify that the target organization is provided
[ -z "${target_org}" ] && echo "Target organization is required." && show_usage && exit 1

# Check if the import path exists
check_import_path "${import_path}"

# Check if project copy JSON output files already exist in the import directory
check_project_copy_files

# Check if mapping file is required and present
check_mapping_file

# Extract project numbers and titles from projects_list.json
project_info=$(extract_project_info "${import_path}" "${projects_list_file}")

# Import all projects
while IFS=$'\t' read -r project_number title source_org; do
    if [[ -n "${specific_project}" && "${specific_project}" == "${project_number}" ]] || [[ -z "${specific_project}" ]]; then
        copy_project "${project_number}" "${source_org}" "${title}"
        export_project_fields "${project_number}"
        link_old_issues "${project_number}"
    fi
done <<< "${project_info}"
