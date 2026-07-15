package context

import (
	"context"
	"fmt"
	"os"
	"sync"

	"github.com/free5gc/nef/internal/logger"
	// "github.com/free5gc/nef/internal/sbi/processor"
	"github.com/free5gc/nef/pkg/factory"
	"github.com/free5gc/openapi/models"
	"github.com/free5gc/openapi/oauth"
	"github.com/golang-jwt/jwt/v4"
	"github.com/google/uuid"
	"strings"
	// "github.com/free5gc/util/httpwrapper"
	"time"
)

type nef interface {
	Config() *factory.Config
}

type NefContext struct {
	nef
	NfService      map[ServiceName]models.NfService
	nfInstID       string // NF Instance ID
	pcfPaUri       string
	udrDrUri       string
	NrfCertPem     string
	numCorreID     uint64
	OAuth2Required bool
	afs            map[string]*AfData
	mu             sync.RWMutex
}

var nefContext = NefContext{}

type Nfcontext interface {
	AuthorizationCheck(token string) error
}

var _ Nfcontext = &NefContext{}

func NewContext(nef nef) (*NefContext, error) {
	c := &NefContext{
		nef:      nef,
		nfInstID: uuid.New().String(),
	}
	c.afs = make(map[string]*AfData)
	logger.CtxLog.Infof("New nfInstID: [%s]", c.nfInstID)
	return c, nil
}

func (c *NefContext) NfInstID() string {
	c.mu.RLock()
	defer c.mu.RUnlock()
	return c.nfInstID
}

func (c *NefContext) SetNfInstID(id string) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.nfInstID = id
	logger.CtxLog.Infof("Set nfInstID: [%s]", c.nfInstID)
}

func (c *NefContext) PcfPaUri() string {
	c.mu.RLock()
	defer c.mu.RUnlock()
	return c.pcfPaUri
}

func (c *NefContext) SetPcfPaUri(uri string) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.pcfPaUri = uri
	logger.CtxLog.Infof("Set pcfPaUri: [%s]", c.pcfPaUri)
}

func (c *NefContext) UdrDrUri() string {
	c.mu.RLock()
	defer c.mu.RUnlock()
	return c.udrDrUri
}

func (c *NefContext) SetUdrDrUri(uri string) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.udrDrUri = uri
	logger.CtxLog.Infof("Set udrDrUri: [%s]", c.udrDrUri)
}
func (c *NefContext) NewAf(afID string) *AfData {
	af := &AfData{
		AfID:     afID,
		Subs:     make(map[string]*AfSubscription),
		PfdTrans: make(map[string]*AfPfdTransaction),
		Log:      logger.CtxLog.WithField(logger.FieldAFID, fmt.Sprintf("AF:%s", afID)),
	}
	return af
}
func (c *NefContext) NewQosAf(scsAsId string) *AfQosData {
	afQos := &AfQosData{
		scsAsID:  scsAsId,
		Subs:     make(map[string]*AfSubscription),
		PfdTrans: make(map[string]*AfPfdTransaction),
		Log:      logger.CtxLog.WithField(logger.FieldAFID, fmt.Sprintf("AF:%s", scsAsId)),
	}
	return afQos
}
func (c *NefContext) AddAf(af *AfData) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.afs[af.AfID] = af
	af.Log.Infoln("AF is added")
}

func (c *NefContext) GetAf(afID string) *AfData {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.afs[afID]
}

func (c *NefContext) DeleteAf(afID string) {
	c.mu.Lock()
	defer c.mu.Unlock()
	delete(c.afs, afID)
	logger.CtxLog.Infof("AF[%s] is deleted", afID)
}

func (c *NefContext) NewCorreID() uint64 {
	c.mu.Lock()
	defer c.mu.Unlock()

	c.numCorreID++
	return c.numCorreID
}

func (c *NefContext) ResetCorreID() {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.numCorreID = 0
}

func (c *NefContext) IsAppIDExisted(appID string) (string, string, bool) {
	c.mu.RLock()
	defer c.mu.RUnlock()
	for _, af := range c.afs {
		af.Mu.RLock()
		if transID, ok := af.IsAppIDExisted(appID); ok {
			defer af.Mu.RUnlock()
			return af.AfID, transID, true
		}
		af.Mu.RUnlock()
	}
	return "", "", false
}

func (c *NefContext) FindAfSub(CorrID string) (*AfData, *AfSubscription) {
	c.mu.RLock()
	defer c.mu.RUnlock()
	for _, af := range c.afs {
		af.Mu.RLock()
		for _, sub := range af.Subs {
			if sub.NotifCorreID == CorrID {
				defer af.Mu.RUnlock()
				return af, sub
			}
		}
		af.Mu.RUnlock()
	}
	return nil, nil
}

func (c *NefContext) GetTokenCtx(serviceName models.ServiceName, targetNF models.NfType) (
	context.Context, *models.ProblemDetails, error,
) {
	if !c.OAuth2Required {
		return context.TODO(), nil, nil
	}
	return oauth.GetTokenCtx(models.NfType_NEF, targetNF,
		c.nfInstID, c.Config().NrfUri(), string(serviceName))
}

func loadJWTSigningKey() ([]byte, error) {
	signingKey := strings.TrimSpace(
		os.Getenv("NEF_OAUTH_JWT_SIGNING_KEY"),
	)

	if len(signingKey) < 32 {
		return nil, fmt.Errorf(
			"NEF_OAUTH_JWT_SIGNING_KEY must contain at least 32 characters",
		)
	}

	return []byte(signingKey), nil
}

func (c *NefContext) AuthorizationCheck(token string) error {
	if !c.OAuth2Required {
		logger.UtilLog.Debug(
			"AuthorizationCheck: OAuth2 not required",
		)

		return nil
	}

	if token == "" {
		logger.UtilLog.Warn(
			"AuthorizationCheck: authorization header is empty",
		)

		return fmt.Errorf("authorization header is empty")
	}

	const bearerPrefix = "Bearer "

	if !strings.HasPrefix(token, bearerPrefix) {
		return fmt.Errorf("authorization scheme must be Bearer")
	}

	token = strings.TrimSpace(
		strings.TrimPrefix(token, bearerPrefix),
	)

	if token == "" {
		return fmt.Errorf("bearer token is empty")
	}

	signingKey, err := loadJWTSigningKey()
	if err != nil {
		logger.UtilLog.Error(
			"AuthorizationCheck: JWT signing key is not configured",
		)

		return fmt.Errorf("OAuth signing key is not configured")
	}

	parsedToken, err := jwt.Parse(
		token,
		func(parsed *jwt.Token) (interface{}, error) {
			if parsed.Method.Alg() != jwt.SigningMethodHS256.Alg() {
				return nil, fmt.Errorf(
					"unexpected signing method: %s",
					parsed.Method.Alg(),
				)
			}

			return signingKey, nil
		},
	)

	if err != nil {
		logger.UtilLog.Warnf(
			"AuthorizationCheck: token validation failed: %v",
			err,
		)

		return fmt.Errorf("invalid token")
	}

	if !parsedToken.Valid {
		return fmt.Errorf("invalid token")
	}

	claims, ok := parsedToken.Claims.(jwt.MapClaims)
	if !ok {
		return fmt.Errorf("invalid token claims")
	}

	if !claims.VerifyIssuer("nef-oauth", true) {
		return fmt.Errorf("invalid token issuer")
	}

	if !claims.VerifyAudience("nef-client", true) {
		return fmt.Errorf("invalid token audience")
	}

	if _, exists := claims["exp"]; !exists {
		return fmt.Errorf("token expiration is missing")
	}

	if !claims.VerifyExpiresAt(time.Now().Unix(), true) {
		return fmt.Errorf("token expired")
	}

	subject, _ := claims["sub"].(string)

	logger.UtilLog.Debugf(
		"AuthorizationCheck: token validated for client [%s]",
		subject,
	)

	return nil
}
