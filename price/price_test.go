package price

import "testing"

// TestRound は、小数第2位への丸め（四捨五入）を確認する。
func TestRound(t *testing.T) {
	// 1.006 は、小数第2位で丸めると 1.01 になる。
	got := Round(1.006)
	want := 1.01

	if got != want {
		t.Errorf("got %.2f, want %.2f", got, want)
	}
}

// TestRoundExact は、すでに小数第2位までの値が変わらないことを確認する。
func TestRoundExact(t *testing.T) {
	if got := Round(2.5); got != 2.5 {
		t.Errorf("got %.2f, want %.2f", got, 2.5)
	}
}
