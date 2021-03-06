#Created by Hao Cheng and Rohan Fernando on 2/22/2015

function sampleEffectsBayesCPi!(nMarkers,
                              xArray,
                              xpx,
                              yCorr,
                              α,
                              δ,
                              vare,
                              varEffects,
                              π,
                              Rinv)

    logPi         = log(π)
    logPiComp     = log(1.0-π)
    logVarEffects = log(varEffects)
    logDelta0     = logPi
    invVarRes     = 1.0/vare
    invVarEffects = 1.0/varEffects
    nLoci = 0

    for j=1:nMarkers
        x = xArray[j]
        rhs = (dot(x.*Rinv,yCorr) + xpx[j]*α[j])*invVarRes
        lhs = xpx[j]*invVarRes + invVarEffects
        invLhs = 1.0/lhs
        gHat   = rhs*invLhs
        logDelta1  = -0.5*(log(lhs) + logVarEffects - gHat*rhs) + logPiComp
        probDelta1 = 1.0/(1.0 + exp(logDelta0 - logDelta1))
        oldAlpha = α[j]

        if(rand()<probDelta1)
            δ[j] = 1
            α[j] = gHat + randn()*sqrt(invLhs)
            BLAS.axpy!(oldAlpha-α[j],x,yCorr)
            nLoci = nLoci + 1
        else
            if (oldAlpha[j]!=0)
                BLAS.axpy!(oldAlpha,x,yCorr)
            end
            δ[j] = 0
            α[j] = 0
        end
    end

    return nLoci
end


function BayesCPi!(options,X,y,C,Rinv)
    ###INPUT
    seed            =   options.seed            # set the seed for the random number generator
    chainLength     =   options.chainLength     # number of iterations
    probFixed       =   options.probFixed       # parameter "pi" the probability SNP effect is zero
    estimatePi      =   options.estimatePi      # "yes" or "no"
    dfEffectVar     =   options.dfEffectVar     # hyper parameter (degrees of freedom) for locus effect variance
    nuRes           =   options.nuRes           # hyper parameter (degrees of freedom) for residual variance
    varGenotypic    =   options.varGenotypic    # used to derive hyper parameter (scale) for locus effect variance
    varResidual     =   options.varResidual     # used to derive hyper parameter (scale) for locus effect variance
    scaleVar        =   varGenotypic*(dfEffectVar-2)/dfEffectVar        # scale factor for locus effects
    scaleRes        =   varResidual*(nuRes-2)/nuRes        # scale factor for residual varianc
    numIter         =   chainLength

    nObs,nMarkers = size(X)
    nFixedEffects = size(C,2)

    ###START

    xArray = get_column_ref(X)
    XpRinvX = getXpRinvX(X, Rinv)

    #initial values
    vare       = varResidual
    markerMeans= center!(X) #centering
    p          = markerMeans/2.0
    mean2pq    = (2*p*(1-p)')[1,1]
    varEffects = varGenotypic/((1-probFixed)*mean2pq)
    mu         = mean(y)
    yCorr      = y - mu
    β          = zeros(nFixedEffects)  # sample of fixed effects
    α          = zeros(nMarkers)       # sample of marker effects
    δ          = zeros(nMarkers)       # inclusion indicator for marker effects
    π          = probFixed
    RinvSqrt   = sqrt(Rinv)

    #return values
    meanFxdEff = zeros(nFixedEffects)
    meanAlpha  = zeros(nMarkers,1)
    mdlFrq     = zeros(nMarkers)
    resVar     = zeros(chainLength)
    genVar     = zeros(chainLength)
    pi         = zeros(chainLength)

    # MCMC sampling
    for i=1:numIter
        # sample residula variance
        vare = sampleVariance(yCorr.*RinvSqrt, nObs, nuRes, scaleRes)
        resVar[i] = vare

        # sample fixed effects
        sampleFixedEffects!(yCorr, nFixedEffects, C, Rinv, β, vare)
        meanFxdEff = meanFxdEff + (β - meanFxdEff)/i

        # sample effects
        nLoci = sampleEffectsBayesCPi!(nMarkers, xArray, XpRinvX, yCorr, α, δ, vare, varEffects, π, Rinv)
        meanAlpha = meanAlpha + (α - meanAlpha)/i
        mdlFrq    = mdlFrq    + (δ - mdlFrq   )/i
        genVar[i] = var(X*α)

        #sameple locus effect variance
        varEffects = sampleVariance(α,nLoci,dfEffectVar, scaleVar)

        if (estimatePi == "yes")
            π = samplePi(nLoci, nMarkers)
        end
        pi[i] = π

        if (i%100)==0
            println ("This is iteration ", i, ", number of loci ", nLoci)
        end
    end

    ###OUTPUT
    output = Dict()
    output["posterior mean of fixed effects"]         = meanFxdEff
    output["posterior mean of marker effects"]        = meanAlpha
    output["model frequency"]                         = mdlFrq
    output["posterior sample of pi"]                  = pi
    output["posterior sample of genotypic variance"]  = genVar
    output["posterior sample of residual variance"]   = resVar

    return output

end
