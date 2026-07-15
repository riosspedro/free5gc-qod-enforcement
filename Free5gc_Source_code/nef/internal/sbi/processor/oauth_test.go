package processor

import (
	"net/http"
	"testing"
	"time"

	qos_models "github.com/free5gc/nef/internal/context"
	"github.com/golang-jwt/jwt/v4"
)

const testJWTSigningKey = "0123456789abcdef0123456789abcdef"

func configureOAuthTestEnvironment(t *testing.T) {
	t.Helper()

	t.Setenv("NEF_OAUTH_CLIENT_ID", "test-client")
	t.Setenv("NEF_OAUTH_CLIENT_SECRET", "test-client-secret")
	t.Setenv("NEF_OAUTH_JWT_SIGNING_KEY", testJWTSigningKey)
}

func TestIssueOAuthTokenSuccess(t *testing.T) {
	configureOAuthTestEnvironment(t)

	processor := &Processor{}

	response := processor.IssueOAuthToken(
		&qos_models.AuthorizationJSON{
			Client_id:     "test-client",
			Client_secret: "test-client-secret",
			Grant_type:    "client_credentials",
		},
	)

	if response.Status != http.StatusOK {
		t.Fatalf(
			"expected status %d, received %d",
			http.StatusOK,
			response.Status,
		)
	}

	body, ok := response.Body.(map[string]interface{})
	if !ok {
		t.Fatal("response body has an unexpected type")
	}

	tokenString, ok := body["access_token"].(string)
	if !ok || tokenString == "" {
		t.Fatal("access token was not returned")
	}

	expiresIn, ok := body["expires_in"].(int)
	if !ok || expiresIn != 3600 {
		t.Fatalf(
			"expected expires_in 3600, received %v",
			body["expires_in"],
		)
	}

	token, err := jwt.Parse(
		tokenString,
		func(token *jwt.Token) (interface{}, error) {
			return []byte(testJWTSigningKey), nil
		},
	)

	if err != nil {
		t.Fatalf("could not parse generated token: %v", err)
	}

	if !token.Valid {
		t.Fatal("generated token is not valid")
	}

	claims, ok := token.Claims.(jwt.MapClaims)
	if !ok {
		t.Fatal("generated token has unexpected claims")
	}

	expiration, ok := claims["exp"].(float64)
	if !ok {
		t.Fatal("generated token does not contain exp")
	}

	if int64(expiration) <= time.Now().Unix() {
		t.Fatal("generated token is already expired")
	}
}

func TestIssueOAuthTokenInvalidSecret(t *testing.T) {
	configureOAuthTestEnvironment(t)

	processor := &Processor{}

	response := processor.IssueOAuthToken(
		&qos_models.AuthorizationJSON{
			Client_id:     "test-client",
			Client_secret: "incorrect-secret",
			Grant_type:    "client_credentials",
		},
	)

	if response.Status != http.StatusUnauthorized {
		t.Fatalf(
			"expected status %d, received %d",
			http.StatusUnauthorized,
			response.Status,
		)
	}
}

func TestIssueOAuthTokenMissingConfiguration(t *testing.T) {
	t.Setenv("NEF_OAUTH_CLIENT_ID", "")
	t.Setenv("NEF_OAUTH_CLIENT_SECRET", "")
	t.Setenv("NEF_OAUTH_JWT_SIGNING_KEY", "")

	processor := &Processor{}

	response := processor.IssueOAuthToken(
		&qos_models.AuthorizationJSON{
			Client_id:     "test-client",
			Client_secret: "test-client-secret",
			Grant_type:    "client_credentials",
		},
	)

	if response.Status != http.StatusInternalServerError {
		t.Fatalf(
			"expected status %d, received %d",
			http.StatusInternalServerError,
			response.Status,
		)
	}
}
