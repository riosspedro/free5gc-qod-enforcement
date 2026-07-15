package processor

import (
	"crypto/subtle"
	"net/http"
	"os"
	"strings"
	"time"

	qos_models "github.com/free5gc/nef/internal/context"
	"github.com/golang-jwt/jwt/v4"
)

const oauthTokenLifetime = time.Hour

type TokenResponse struct {
	AccessToken string `json:"access_token"`
	TokenType   string `json:"token_type"`
	ExpiresIn   int    `json:"expires_in"`
}

type Response struct {
	Status int
	Body   interface{}
}

func loadOAuthConfiguration() (
	clientID string,
	clientSecret string,
	signingKey []byte,
	valid bool,
) {
	clientID = strings.TrimSpace(
		os.Getenv("NEF_OAUTH_CLIENT_ID"),
	)

	clientSecret = strings.TrimSpace(
		os.Getenv("NEF_OAUTH_CLIENT_SECRET"),
	)

	signingKeyText := strings.TrimSpace(
		os.Getenv("NEF_OAUTH_JWT_SIGNING_KEY"),
	)

	signingKey = []byte(signingKeyText)

	valid = clientID != "" &&
		clientSecret != "" &&
		len(signingKey) >= 32

	return
}

func invalidClientResponse() *Response {
	return &Response{
		Status: http.StatusUnauthorized,
		Body: map[string]interface{}{
			"error":             "invalid_client",
			"error_description": "Invalid client credentials",
		},
	}
}

func oauthConfigurationErrorResponse() *Response {
	return &Response{
		Status: http.StatusInternalServerError,
		Body: map[string]interface{}{
			"error":             "server_error",
			"error_description": "OAuth server configuration is incomplete",
		},
	}
}

func (p *Processor) IssueOAuthToken(
	authReq *qos_models.AuthorizationJSON,
) *Response {
	if authReq == nil {
		return &Response{
			Status: http.StatusBadRequest,
			Body: map[string]interface{}{
				"error":             "invalid_request",
				"error_description": "Authorization request is required",
			},
		}
	}

	if authReq.Grant_type != "client_credentials" {
		return &Response{
			Status: http.StatusBadRequest,
			Body: map[string]interface{}{
				"error":             "unsupported_grant_type",
				"error_description": "Only client_credentials is supported",
			},
		}
	}

	validClientID,
		validClientSecret,
		jwtSigningKey,
		configurationValid := loadOAuthConfiguration()

	if !configurationValid {
		return oauthConfigurationErrorResponse()
	}

	clientIDMatches := subtle.ConstantTimeCompare(
		[]byte(authReq.Client_id),
		[]byte(validClientID),
	) == 1

	clientSecretMatches := subtle.ConstantTimeCompare(
		[]byte(authReq.Client_secret),
		[]byte(validClientSecret),
	) == 1

	if !clientIDMatches || !clientSecretMatches {
		return invalidClientResponse()
	}

	now := time.Now()
	expiresAt := now.Add(oauthTokenLifetime)

	token := jwt.NewWithClaims(
		jwt.SigningMethodHS256,
		jwt.MapClaims{
			"iss":   "nef-oauth",
			"sub":   authReq.Client_id,
			"aud":   "nef-client",
			"scope": "qos-control",
			"iat":   now.Unix(),
			"exp":   expiresAt.Unix(),
		},
	)

	tokenString, err := token.SignedString(jwtSigningKey)
	if err != nil {
		return &Response{
			Status: http.StatusInternalServerError,
			Body: map[string]interface{}{
				"error":             "server_error",
				"error_description": "Could not generate token",
			},
		}
	}

	return &Response{
		Status: http.StatusOK,
		Body: map[string]interface{}{
			"access_token": tokenString,
			"token_type":   "Bearer",
			"expires_in":   int(oauthTokenLifetime.Seconds()),
			"scope":        "qos-control",
		},
	}
}
