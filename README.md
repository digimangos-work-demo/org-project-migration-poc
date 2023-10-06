# GitHub Project Migration Scripts

These scripts are designed to help you migrate GitHub projects and their associated issues from one organization to another. The migration process involves exporting project data from the source organization and then importing it into the target organization. The following scripts are included:

1. `export_projects.sh`: This script exports project data from a source organization.
2. `import_projects.sh`: This script imports projects and associated issues into a target organization.

Before you begin, make sure you have the GitHub CLI (`gh`) installed and authenticated with the required permissions. You can grant the necessary permissions by executing:

```bash
gh auth refresh -s project
```

## Export Script: `export_projects.sh`

### Usage

```bash
./export_projects.sh -o <organization_name> [-p <export_path>]
```

### Parameters

- `-o <organization_name>`: Specifies the name of the source organization.
- `-p <export_path>` (optional): Specifies the export path where project data will be saved. If not provided, it defaults to the `export` directory.

### Example

To export projects from the organization "example-org" and save the data in the "my-export" directory, run the following command:

```bash
./export_projects.sh -o example-org -p my-export
```

## Import Script: `import_projects.sh`

### Usage

```bash
./import_projects.sh -o <target_organization> [-m <repository_mapping_file>] [-p <projects_list_file>] [-i <import_path>] [-n] [-e] [-s <specific_project_number>]
```

### Parameters

- `-o <target_organization>`: Specifies the name of the target organization where projects will be imported.
- `-m <repository_mapping_file>` (optional): Specifies the mapping file that maps repositories from the source to the target organization. If not provided, repository names will be used as-is.
- `-p <projects_list_file>` (optional): Specifies the file containing project information exported from the source organization. If not provided, it looks for `projects_list.json` in the import path.
- `-i <import_path>` (optional): Specifies the import path where exported project data is located. If not provided, it defaults to the `export` directory.
- `-n` (optional): Ignores the mapping file and uses the same repository names.
- `-e` (optional): Uses existing project copy JSON output files if they already exist. If not specified, the script checks for the existence of these files and performs the project copy if they don't exist.
- `-s <specific_project_number>` (optional): Imports a specific project by providing its number.

### Example

To import projects into the organization "new-org" from the data in the "my-export" directory, run the following command:

```bash
./import_projects.sh -o new-org -i my-export
```

## Mapping File Example

If you choose to use a mapping file (`-m` option), it should be in CSV format, where each line maps a source repository to a target repository. For example:

```csv
source_repo_1,target_repo_1
source_repo_2,target_repo_2
source_repo_3,target_repo_3
```

The script will use this mapping to remap repository references during the import process.

Please note that you should perform the export using `export_projects.sh` before running the import script `import_projects.sh`. Additionally, ensure that you have the required permissions for both source and target organizations.

Feel free to customize the scripts and adapt them to your specific needs.

