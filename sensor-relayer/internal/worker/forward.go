package worker

import (
	"bytes"
	"fmt"
	"io"
	"mime/multipart"
	"net/http"
	"strconv"

	"github.com/ayussh-2/profiler/sensor-relayer/internal/models"
)

type Forwarder struct {
	queue      chan *models.FusedPayload
	metrics    *models.Metrics
	backendURL string
	client     *http.Client
}

func NewForwarder(q chan *models.FusedPayload, m *models.Metrics, backendURL string, client *http.Client) *Forwarder {
	return &Forwarder{
		queue:      q,
		metrics:    m,
		backendURL: backendURL,
		client:     client,
	}
}

func (f *Forwarder) Forward(p *models.FusedPayload) error {
	var body bytes.Buffer
	mw := multipart.NewWriter(&body)

	fw, err := mw.CreateFormFile("image", "frame.jpg")
	if err != nil {
		return fmt.Errorf("create form file: %w", err)
	}
	if _, err = fw.Write(p.ImageBytes); err != nil {
		return fmt.Errorf("write image: %w", err)
	}

	fields := map[string]string{
		"depth_mm":     strconv.FormatFloat(p.DepthMM, 'f', 2, 64),
		"lat":          strconv.FormatFloat(p.Lat, 'f', 7, 64),
		"lng":          strconv.FormatFloat(p.Lng, 'f', 7, 64),
		"relayed_at":   strconv.FormatInt(p.FusedAt.UnixMilli(), 10),
		"time_diff_ms": strconv.FormatInt(p.TimeDiffMs, 10),
	}
	for k, v := range fields {
		if err = mw.WriteField(k, v); err != nil {
			return fmt.Errorf("write field %s: %w", k, err)
		}
	}

	if err = mw.Close(); err != nil {
		return fmt.Errorf("close writer: %w", err)
	}

	req, err := http.NewRequest(http.MethodPost, f.backendURL, &body)
	if err != nil {
		return fmt.Errorf("new request: %w", err)
	}
	req.Header.Set("Content-Type", mw.FormDataContentType())

	resp, err := f.client.Do(req)
	if err != nil {
		return fmt.Errorf("http do: %w", err)
	}
	defer resp.Body.Close()
	io.Copy(io.Discard, resp.Body)

	if resp.StatusCode >= 300 {
		return fmt.Errorf("backend returned %s", resp.Status)
	}
	return nil
}
