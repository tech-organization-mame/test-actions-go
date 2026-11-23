// Package price は、価格の丸めを提供する。
// 検証用のサンプル。CIの失敗を、意図的に作るために使う。
package price

import "math"

// Round は、v を小数第2位に丸める（四捨五入）。
func Round(v float64) float64 {
	return math.Floor(v*100) / 100
}
