# Training the LeafDoctor CoreML model

KolaCare runs without a model (it falls back to on-device colour analysis), but the
full experience — naming the exact disease — uses a Create ML image classifier
called **LeafDoctor**.

## 1. Get the data

| Dataset | Use | Licence |
|---|---|---|
| [PlantVillage](https://github.com/spMohanty/PlantVillage-Dataset) (`raw/color`) | Tomato, potato, pepper/chilli and maize classes | CC BY-SA 4.0 |
| A public rice-leaf dataset (e.g. "Rice Leaf Diseases" on UCI / Kaggle) | Rice blast, brown spot, bacterial leaf blight, healthy | see dataset |

## 2. Build a balanced train/test split

```bash
python3 ModelTraining/prepare_dataset.py \
  --plantvillage ~/Downloads/PlantVillage-Dataset/raw/color \
  --rice ~/Downloads/rice_leaf_diseases \
  --out ~/Datasets/kolacare --per-class 600
```

Folder names become the model's class labels and must match `modelLabels` in
`KolaCare/Resources/diseases.json` (case and punctuation are ignored).

## 3. Train with Create ML

```bash
swift ModelTraining/TrainLeafDoctor.swift ~/Datasets/kolacare ~/Desktop/LeafDoctor.mlmodel
```

The script prints training, validation and test accuracy plus the confusion matrix —
copy these into the report's testing chapter. (Alternatively open the Create ML app,
choose *Image Classification*, point it at `train/` and `test/`, enable the same
augmentations and export `LeafDoctor.mlmodel`.)

## 4. Add it to the app

1. Drag `LeafDoctor.mlmodel` into `KolaCare/Resources` in Xcode.
2. Make sure the **KolaCare** target is ticked.
3. Build and run. Settings › On-device AI now shows *CoreML disease model* and
   *LeafDoctor.mlmodel*.

The app loads the compiled model by name (`LeafDoctor.mlmodelc`) through
`CoreMLLeafClassifier.loadBundled()`, so no code changes are needed.
