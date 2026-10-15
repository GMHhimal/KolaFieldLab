#!/usr/bin/env python3
"""Builds the KolaCare training set from PlantVillage (and optionally a rice
leaf dataset) with a stratified 80/20 train/test split.

usage:
  python3 prepare_dataset.py --plantvillage ~/Downloads/PlantVillage-Dataset/raw/color \
                             [--rice ~/Downloads/rice_leaf_diseases] \
                             --out ~/Datasets/kolacare --per-class 600

PlantVillage: https://github.com/spMohanty/PlantVillage-Dataset (raw/color)
Rice: any dataset with one folder per class; map folder names with --rice-map.
"""
import argparse, json, random, shutil
from pathlib import Path

PLANTVILLAGE_CLASSES = [
    "Tomato___Early_blight", "Tomato___Late_blight", "Tomato___Leaf_Mold", "Tomato___Septoria_leaf_spot",
    "Tomato___Bacterial_spot", "Tomato___Tomato_Yellow_Leaf_Curl_Virus", "Tomato___Tomato_mosaic_virus",
    "Tomato___Spider_mites Two-spotted_spider_mite", "Tomato___Target_Spot", "Tomato___healthy",
    "Potato___Early_blight", "Potato___Late_blight", "Potato___healthy",
    "Pepper,_bell___Bacterial_spot", "Pepper,_bell___healthy",
    "Corn_(maize)___Common_rust_", "Corn_(maize)___Northern_Leaf_Blight",
    "Corn_(maize)___Cercospora_leaf_spot Gray_leaf_spot", "Corn_(maize)___healthy",
]

DEFAULT_RICE_MAP = {
    "Leaf smut": None,  # not in KolaCare's catalogue
    "Bacterial leaf blight": "Rice___Bacterial_leaf_blight",
    "Brown spot": "Rice___Brown_Spot",
    "LeafBlast": "Rice___Leaf_Blast",
    "BrownSpot": "Rice___Brown_Spot",
    "Healthy": "Rice___Healthy",
}

IMAGE_EXT = {".jpg", ".jpeg", ".png"}

def copy_split(files, label, out, test_ratio, rng):
    rng.shuffle(files)
    cut = max(1, int(len(files) * test_ratio))
    for split, chunk in (("test", files[:cut]), ("train", files[cut:])):
        dest = out / split / label
        dest.mkdir(parents=True, exist_ok=True)
        for f in chunk:
            shutil.copy2(f, dest / f.name)
    return len(files) - cut, cut

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--plantvillage", type=Path, required=True)
    ap.add_argument("--rice", type=Path)
    ap.add_argument("--rice-map", type=str, help="JSON mapping of rice folder name -> KolaCare label")
    ap.add_argument("--out", type=Path, required=True)
    ap.add_argument("--per-class", type=int, default=600)
    ap.add_argument("--test-ratio", type=float, default=0.2)
    ap.add_argument("--seed", type=int, default=42)
    args = ap.parse_args()

    rng = random.Random(args.seed)
    summary = {}
    for label in PLANTVILLAGE_CLASSES:
        folder = args.plantvillage / label
        if not folder.is_dir():
            print(f"! missing {folder}")
            continue
        files = sorted(p for p in folder.iterdir() if p.suffix.lower() in IMAGE_EXT)[: args.per_class * 3]
        files = rng.sample(files, min(args.per_class, len(files)))
        summary[label] = copy_split(files, label, args.out, args.test_ratio, rng)

    if args.rice:
        mapping = json.loads(args.rice_map) if args.rice_map else DEFAULT_RICE_MAP
        for folder in sorted(p for p in args.rice.iterdir() if p.is_dir()):
            label = mapping.get(folder.name)
            if not label:
                continue
            files = sorted(p for p in folder.rglob("*") if p.suffix.lower() in IMAGE_EXT)
            files = rng.sample(files, min(args.per_class, len(files)))
            summary[label] = copy_split(files, label, args.out, args.test_ratio, rng)

    print(f"{'class':55} train  test")
    for label, (train, test) in summary.items():
        print(f"{label:55} {train:5} {test:5}")
    print(f"→ {args.out}")

if __name__ == "__main__":
    main()
