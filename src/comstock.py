import tarfile
import pandas as pd

from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
from tempfile import TemporaryDirectory
from urllib.request import urlretrieve


def load_comstock(path):
    """
    Load a ComStock dataset from a gzipped TAR archive.
    Each archive contains one CSV file with building characteristics,
    energy consumption, emissions, and simulation results.
    Parameters:
    path : str or Path
    Returns: pd.DataFrame (ComStock data loaded into a DataFrame.)
    """
    with tarfile.open(path, "r:gz") as archive:
        csv_members = [
            member for member in archive.getmembers()
            if member.isfile() and member.name.endswith(".csv")]
        if len(csv_members) != 1:
            raise ValueError(f"Expected one CSV file, found {len(csv_members)}")
        with archive.extractfile(csv_members[0]) as csv_file:
            df = pd.read_csv(csv_file, low_memory=False)

    return df


def validate_upgrade(baseline, upgrade, measure_flag=None):
    """
    Check whether a ComStock upgrade can be compared with the baseline.
    Matches records by building ID and census tract, checks for duplicates
    and unmatched records, and summarizes upgrade applicability and
    simulation success.

    Parameters:
    baseline : pd.DataFrame (ComStock baseline dataset (upgrade 0)).
    upgrade : pd.DataFrame (ComStock dataset for an upgrade scenario).
    measure_flag : str, optional (Name of a measure-specific applicability 
    column to compare with the general applicability flag).

    Returns: pd.Series (summary of matching, applicability, and simulation checks).
    """
    keys = ["bldg_id", "in.nhgis_tract_gisjoin"]
    baseline_keys = pd.MultiIndex.from_frame(baseline[keys])
    upgrade_keys = pd.MultiIndex.from_frame(upgrade[keys])
    applicable = upgrade["applicability"]
    successful = upgrade["completed_status"].eq("Success")

    results = {
        "same_columns": set(baseline.columns) == set(upgrade.columns),
        "duplicate_baseline_keys": baseline.duplicated(keys).sum(),
        "duplicate_upgrade_keys": upgrade.duplicated(keys).sum(),
        "unmatched_baseline_keys": len(baseline_keys.difference(upgrade_keys)),
        "unmatched_upgrade_keys": len(upgrade_keys.difference(baseline_keys)),
        "applicable_records": applicable.sum(),
        "successful_records": successful.sum(),
        "applicability_matches_success": applicable.equals(successful),
        "applicable_buildings": upgrade.loc[applicable, "bldg_id"].nunique()}

    if measure_flag is not None:
        results["measure_flag_matches"] = applicable.equals(upgrade[measure_flag])

    return pd.Series(results)



def validate_single_upgrade(upgrade_id, baseline, comstock_dir, base_url):
    """
    Download and validate one ComStock upgrade.
    Uses an existing local file when available. Otherwise, downloads
    the archive temporarily and removes it after validation.

    Parameters: 
    upgrade_id : int (ID of the upgrade scenario).
    baseline : pd.DataFrame (Baseline data containing the required validation columns).
    comstock_dir : str or Path (Directory containing local ComStock files).
    base_url : str (URL of the remote ComStock directory).

    Returns: dict (Upgrade ID and validation results).
    """
    columns = ["bldg_id", "in.nhgis_tract_gisjoin", "applicability", "completed_status"]

    filename = f"MA_G2500250_upgrade{upgrade_id}.csv.gz"
    local_path = Path(comstock_dir) / filename

    with TemporaryDirectory() as temp_dir:
        path = local_path
        if not path.is_file():
            path = Path(temp_dir) / filename
            urlretrieve(f"{base_url.rstrip('/')}/{filename}", path)
        with tarfile.open(path, "r:gz") as archive:
            members = [
                member for member in archive.getmembers()
                if member.isfile() and member.name.endswith(".csv") ]
            if len(members) != 1:
                raise ValueError(f"Expected one CSV, found {len(members)}")
            with archive.extractfile(members[0]) as csv_file:
                upgrade = pd.read_csv(csv_file, usecols=columns)
        validation = validate_upgrade(baseline, upgrade)

    return {"upgrade_id": upgrade_id, **validation.to_dict(), "error": None}


def validate_all_upgrades(baseline, comstock_dir, base_url):
    """
    Validate all 65 ComStock upgrades in parallel.
    Processes up to four upgrades simultaneously and records any
    errors without interrupting the remaining validations.

    Parameters:
    baseline : pd.DataFrame (ComStock baseline dataset).
    comstock_dir : str or Path (Directory containing local ComStock files).
    base_url : str (URL of the remote ComStock directory).

    Returns:
    pd.DataFrame (Validation summary for all 65 upgrade scenarios).
    """
    columns = ["bldg_id", "in.nhgis_tract_gisjoin", "applicability", "completed_status"]
    baseline_subset = baseline[columns]
    results = []

    with ThreadPoolExecutor(max_workers=4) as executor:
        futures = {
            executor.submit(
                validate_single_upgrade,
                upgrade_id,
                baseline_subset,
                comstock_dir,
                base_url
            ): upgrade_id
            for upgrade_id in range(1, 66)}
        for future in as_completed(futures):
            upgrade_id = futures[future]
            try:
                results.append(future.result())
                print(f"Upgrade {upgrade_id}: OK")
            except Exception as exc:
                results.append({
                    "upgrade_id": upgrade_id,
                    "error": str(exc)})
                print(f"Upgrade {upgrade_id}: FAILED - {exc}")

    return pd.DataFrame(results).sort_values("upgrade_id").reset_index(drop=True)