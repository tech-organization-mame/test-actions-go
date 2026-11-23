package cart

import "testing"

func TestTotal(t *testing.T) {
	if got := Total([]int{1000, 2000}); got != 3300 {
		t.Errorf("Total = %d, want 3300", got)
	}
}

func TestTax(t *testing.T) {
	if got := Tax([]int{1000, 2000}); got != 300 {
		t.Errorf("Tax = %d, want 300", got)
	}
}

func TestReceipt(t *testing.T) {
	want := "小計 1500円 / 税 150円 / 合計 1650円"
	if got := Receipt([]int{500, 1000}); got != want {
		t.Errorf("Receipt = %q, want %q", got, want)
	}
}

func TestSubtotal(t *testing.T) {
	if got := Subtotal([]int{100, 200, 300}); got != 600 {
		t.Errorf("Subtotal = %d, want 600", got)
	}
}
