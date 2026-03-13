"""
ML model training for material/asphalt mix estimation.

Usage (from backend/):
    python -m training.material_estimator_trainer
    python -m training.material_estimator_trainer --data data/sample_repair_data.csv --model gradient_boosting --test
"""

import argparse
import sys
from pathlib import Path

import numpy as np
import pandas as pd
import joblib
from sklearn.model_selection import train_test_split, cross_val_score
from sklearn.ensemble import RandomForestRegressor, GradientBoostingRegressor
from sklearn.preprocessing import StandardScaler
from sklearn.metrics import mean_absolute_error, mean_squared_error, r2_score

FEATURE_COLUMNS = ['area_m2', 'depth_m', 'volume_liters']
TARGET_COLUMNS = ['hotmix_kg', 'tack_coat_liters', 'aggregate_base_kg']

BACKEND_DIR = Path(__file__).resolve().parent.parent
DEFAULT_MODEL_DIR = BACKEND_DIR / 'models' / 'material_estimator'
DEFAULT_DATA_PATH = BACKEND_DIR / 'data' / 'sample_repair_data.csv'


class MaterialEstimatorML:
    def __init__(self, model_type='random_forest'):
        self.model_type = model_type
        self.models = {}
        self.scalers = {}

    def load_data(self, csv_path: str) -> pd.DataFrame:
        df = pd.read_csv(csv_path)

        required = FEATURE_COLUMNS + TARGET_COLUMNS
        missing = [c for c in required if c not in df.columns]
        if missing:
            raise ValueError(f"Missing columns: {missing}")
        if len(df) < 5:
            raise ValueError(f"Need at least 5 records, got {len(df)}")

        df = df.dropna()
        print(f"[TRAIN] Loaded {len(df)} records")
        for col in FEATURE_COLUMNS:
            print(f"  {col}: {df[col].min():.4f} - {df[col].max():.4f}")

        return df

    def train(self, df: pd.DataFrame, test_size=0.2, random_state=42):
        X = df[FEATURE_COLUMNS]

        X_train, X_test, idx_train, idx_test = train_test_split(
            X, range(len(X)), test_size=test_size, random_state=random_state
        )

        print(f"\n[TRAIN] Split: {len(X_train)} train, {len(X_test)} test")

        for target in TARGET_COLUMNS:
            print(f"\n--- {target} ---")
            y_train = df.loc[idx_train, target].values
            y_test = df.loc[idx_test, target].values

            scaler = StandardScaler()
            X_train_scaled = scaler.fit_transform(X_train)
            X_test_scaled = scaler.transform(X_test)

            if self.model_type == 'random_forest':
                model = RandomForestRegressor(
                    n_estimators=100, max_depth=10,
                    min_samples_split=5, min_samples_leaf=2,
                    random_state=random_state, n_jobs=-1
                )
            else:
                model = GradientBoostingRegressor(
                    n_estimators=100, learning_rate=0.1,
                    max_depth=5, random_state=random_state
                )

            model.fit(X_train_scaled, y_train)

            y_pred = model.predict(X_test_scaled)
            mae = mean_absolute_error(y_test, y_pred)
            rmse = np.sqrt(mean_squared_error(y_test, y_pred))
            r2 = r2_score(y_test, y_pred)
            cv_scores = cross_val_score(
                model, X_train_scaled, y_train, cv=5,
                scoring='neg_mean_absolute_error'
            )

            print(f"  MAE:  {mae:.4f}")
            print(f"  RMSE: {rmse:.4f}")
            print(f"  R2:   {r2:.4f}")
            print(f"  CV MAE (5-fold): {-cv_scores.mean():.4f}")

            if hasattr(model, 'feature_importances_'):
                print("  Feature importance:")
                for feat, imp in zip(FEATURE_COLUMNS, model.feature_importances_):
                    print(f"    {feat}: {imp:.3f}")

            self.models[target] = model
            self.scalers[target] = scaler

    def predict(self, area_m2: float, depth_m: float, volume_liters: float) -> dict:
        X = pd.DataFrame([[area_m2, depth_m, volume_liters]], columns=FEATURE_COLUMNS)
        predictions = {}

        for target in TARGET_COLUMNS:
            X_scaled = self.scalers[target].transform(X)
            pred = self.models[target].predict(X_scaled)[0]
            predictions[target] = max(0, pred)

        return {
            "hotmix_kg": round(predictions['hotmix_kg'], 2),
            "tack_coat_liters": round(predictions['tack_coat_liters'], 3),
            "aggregate_base_kg": round(predictions['aggregate_base_kg'], 2),
        }

    def save(self, save_dir: str = None):
        save_dir = Path(save_dir or DEFAULT_MODEL_DIR)
        save_dir.mkdir(parents=True, exist_ok=True)

        for target in TARGET_COLUMNS:
            joblib.dump(self.models[target], save_dir / f"material_{target}.pkl")
            joblib.dump(self.scalers[target], save_dir / f"scaler_{target}.pkl")
            print(f"[SAVE] {target} -> {save_dir}")

    def load(self, load_dir: str = None) -> bool:
        load_dir = Path(load_dir or DEFAULT_MODEL_DIR)

        for target in TARGET_COLUMNS:
            model_file = load_dir / f"material_{target}.pkl"
            scaler_file = load_dir / f"scaler_{target}.pkl"
            try:
                self.models[target] = joblib.load(model_file)
                self.scalers[target] = joblib.load(scaler_file)
            except FileNotFoundError:
                print(f"[LOAD] Not found: {model_file}")
                return False

        print(f"[LOAD] All models loaded from {load_dir}")
        return True


def main():
    parser = argparse.ArgumentParser(description='Train material/asphalt mix estimation ML model')
    parser.add_argument('--data', type=str, default=str(DEFAULT_DATA_PATH),
                        help='Path to training CSV')
    parser.add_argument('--model', type=str, default='random_forest',
                        choices=['random_forest', 'gradient_boosting'])
    parser.add_argument('--save-dir', type=str, default=str(DEFAULT_MODEL_DIR))
    parser.add_argument('--test', action='store_true', help='Run test predictions after training')

    args = parser.parse_args()

    print(f"[TRAIN] Model type: {args.model}")
    print(f"[TRAIN] Data: {args.data}")
    print(f"[TRAIN] Output: {args.save_dir}")

    trainer = MaterialEstimatorML(model_type=args.model)
    df = trainer.load_data(args.data)
    trainer.train(df)
    trainer.save(args.save_dir)

    if args.test:
        print("\n--- Test Predictions ---")
        test_cases = [
            (0.05, 0.02, 0.1, "Small (LOW)"),
            (0.15, 0.05, 0.5, "Medium"),
            (0.3, 0.1, 2.0, "Large (HIGH)"),
            (0.5, 0.15, 3.0, "Critical"),
        ]
        for area, depth, volume, label in test_cases:
            pred = trainer.predict(area, depth, volume)
            print(f"\n  {label}: area={area}m2, depth={depth}m, vol={volume}L")
            print(f"    HMA: {pred['hotmix_kg']}kg, Tack: {pred['tack_coat_liters']}L, Aggregate: {pred['aggregate_base_kg']}kg")

    sys.path.insert(0, str(BACKEND_DIR))
    from utils.material_estimator import enable_ml_mode
    if enable_ml_mode(args.save_dir):
        print("\n[OK] ML mode verified -- ready for inference")
    else:
        print("\n[WARN] ML mode could not load trained models")
        return False

    return True


if __name__ == '__main__':
    success = main()
    sys.exit(0 if success else 1)
