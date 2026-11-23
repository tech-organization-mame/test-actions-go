// Package cart は、カートの合計金額と、レシートの計算を提供する。
// 検証用のサンプル。
package cart

import (
	"fmt"
	"math"
)

// Subtotal は、税抜きの合計。
func Subtotal(prices []int) int {
	sum := 0
	for _, p := range prices {
		sum += p
	}
	return sum
}

// Total は、税込みの合計（円未満は四捨五入）。
func Total(prices []int) int {
	return int(math.Round(float64(Subtotal(prices)) * (1 + TaxRate)))
}

// Tax は、税額。
func Tax(prices []int) int {
	return Total(prices) - Subtotal(prices)
}

// Receipt は、レシートの1行を返す。
func Receipt(prices []int) string {
	return fmt.Sprintf("小計 %d円 / 税 %d円 / 合計 %d円", Subtotal(prices), Tax(prices), Total(prices))
}
