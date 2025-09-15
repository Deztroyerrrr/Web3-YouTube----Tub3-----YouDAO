(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-insufficient-funds (err u102))
(define-constant err-unauthorized (err u103))
(define-constant err-already-exists (err u104))
(define-constant err-invalid-input (err u105))
(define-constant err-voting-ended (err u106))
(define-constant err-subscription-expired (err u107))
(define-constant err-subscription-not-found (err u108))

(define-fungible-token tub3-token)

(define-non-fungible-token video-clip uint)

(define-data-var next-video-id uint u1)
(define-data-var next-clip-id uint u1)
(define-data-var next-proposal-id uint u1)
(define-data-var platform-fee-rate uint u500)

(define-map videos
    { video-id: uint }
    {
        creator: principal,
        title: (string-ascii 100),
        ipfs-hash: (string-ascii 100),
        duration: uint,
        upload-block: uint,
        total-views: uint,
        total-revenue: uint,
        status: (string-ascii 20)
    }
)

(define-map user-profiles
    { user: principal }
    {
        username: (string-ascii 50),
        reputation: uint,
        total-earnings: uint,
        videos-created: uint,
        videos-watched: uint
    }
)

(define-map video-clips
    { clip-id: uint }
    {
        video-id: uint,
        owner: principal,
        title: (string-ascii 100),
        start-time: uint,
        end-time: uint,
        mint-block: uint,
        rarity-score: uint
    }
)

(define-map watch-sessions
    { video-id: uint, viewer: principal }
    {
        watch-time: uint,
        completion-rate: uint,
        last-watch-block: uint,
        reward-claimed: bool
    }
)

(define-map ad-campaigns
    { campaign-id: uint }
    {
        advertiser: principal,
        budget: uint,
        per-view-payout: uint,
        target-views: uint,
        current-views: uint,
        active: bool
    }
)

(define-map dao-proposals
    { proposal-id: uint }
    {
        proposer: principal,
        target-video: uint,
        proposal-type: (string-ascii 20),
        description: (string-ascii 200),
        votes-for: uint,
        votes-against: uint,
        voting-deadline: uint,
        executed: bool
    }
)

(define-map dao-votes
    { proposal-id: uint, voter: principal }
    { vote: bool, voting-power: uint }
)

(define-map creator-subscriptions
    { creator: principal }
    {
        subscription-price: uint,
        total-subscribers: uint,
        monthly-revenue: uint,
        active: bool
    }
)

(define-map user-subscriptions
    { subscriber: principal, creator: principal }
    {
        start-block: uint,
        expiry-block: uint,
        monthly-payment: uint,
        auto-renew: bool
    }
)

(define-private (is-contract-owner)
    (is-eq tx-sender contract-owner)
)

(define-private (get-user-reputation (user principal))
    (default-to u0 (get reputation (map-get? user-profiles { user: user })))
)

(define-private (calculate-voting-power (user principal))
    (let ((reputation (get-user-reputation user))
          (balance (ft-get-balance tub3-token user)))
        (+ reputation (/ balance u1000))
    )
)

(define-private (distribute-ad-revenue (video-id uint) (amount uint))
    (let ((video-data (unwrap! (map-get? videos { video-id: video-id }) (err u0)))
          (creator (get creator video-data))
          (platform-fee (/ (* amount (var-get platform-fee-rate)) u10000))
          (creator-share (- amount platform-fee)))
        (begin
            (try! (ft-mint? tub3-token creator-share creator))
            (try! (ft-mint? tub3-token platform-fee contract-owner))
            (map-set videos { video-id: video-id }
                (merge video-data { total-revenue: (+ (get total-revenue video-data) amount) }))
            (ok true)
        )
    )
)

(define-private (is-subscription-active (subscriber principal) (creator principal))
    (match (map-get? user-subscriptions { subscriber: subscriber, creator: creator })
        subscription (>= (get expiry-block subscription) stacks-block-height)
        false
    )
)

(define-private (process-subscription-payment (subscriber principal) (creator principal) (amount uint))
    (let ((platform-fee (/ (* amount (var-get platform-fee-rate)) u10000))
          (creator-share (- amount platform-fee)))
        (begin
            (try! (ft-transfer? tub3-token amount subscriber contract-owner))
            (try! (ft-mint? tub3-token creator-share creator))
            (ok true)
        )
    )
)

(define-public (create-profile (username (string-ascii 50)))
    (let ((user tx-sender))
        (if (is-some (map-get? user-profiles { user: user }))
            err-already-exists
            (ok (map-set user-profiles { user: user }
                {
                    username: username,
                    reputation: u100,
                    total-earnings: u0,
                    videos-created: u0,
                    videos-watched: u0
                }
            ))
        )
    )
)

(define-public (upload-video (title (string-ascii 100)) (ipfs-hash (string-ascii 100)) (duration uint))
    (let ((video-id (var-get next-video-id))
          (creator tx-sender))
        (asserts! (> (len title) u0) err-invalid-input)
        (asserts! (> (len ipfs-hash) u0) err-invalid-input)
        (asserts! (> duration u0) err-invalid-input)
        
        (map-set videos { video-id: video-id }
            {
                creator: creator,
                title: title,
                ipfs-hash: ipfs-hash,
                duration: duration,
                upload-block: stacks-block-height,
                total-views: u0,
                total-revenue: u0,
                status: "active"
            }
        )
        
        (let ((profile (default-to 
                { username: "", reputation: u100, total-earnings: u0, videos-created: u0, videos-watched: u0 }
                (map-get? user-profiles { user: creator }))))
            (map-set user-profiles { user: creator }
                (merge profile { videos-created: (+ (get videos-created profile) u1) }))
        )
        
        (var-set next-video-id (+ video-id u1))
        (ok video-id)
    )
)

(define-public (watch-video (video-id uint) (watch-duration uint))
    (let ((video-data (unwrap! (map-get? videos { video-id: video-id }) err-not-found))
          (viewer tx-sender)
          (completion-rate (/ (* watch-duration u100) (get duration video-data))))
        
        (asserts! (is-eq (get status video-data) "active") err-unauthorized)
        (asserts! (> watch-duration u0) err-invalid-input)
        
        (map-set watch-sessions { video-id: video-id, viewer: viewer }
            {
                watch-time: watch-duration,
                completion-rate: completion-rate,
                last-watch-block: stacks-block-height,
                reward-claimed: false
            }
        )
        
        (map-set videos { video-id: video-id }
            (merge video-data { total-views: (+ (get total-views video-data) u1) }))
        
        (let ((profile (default-to 
                { username: "", reputation: u100, total-earnings: u0, videos-created: u0, videos-watched: u0 }
                (map-get? user-profiles { user: viewer }))))
            (map-set user-profiles { user: viewer }
                (merge profile { videos-watched: (+ (get videos-watched profile) u1) }))
        )
        
        (ok completion-rate)
    )
)

(define-public (claim-watch-reward (video-id uint))
    (let ((session (unwrap! (map-get? watch-sessions { video-id: video-id, viewer: tx-sender }) err-not-found))
          (completion-rate (get completion-rate session)))
        
        (asserts! (not (get reward-claimed session)) err-unauthorized)
        (asserts! (>= completion-rate u50) err-unauthorized)
        
        (let ((reward-amount (* completion-rate u10)))
            (try! (ft-mint? tub3-token reward-amount tx-sender))
            
            (map-set watch-sessions { video-id: video-id, viewer: tx-sender }
                (merge session { reward-claimed: true }))
            
            (let ((profile (default-to 
                    { username: "", reputation: u100, total-earnings: u0, videos-created: u0, videos-watched: u0 }
                    (map-get? user-profiles { user: tx-sender }))))
                (map-set user-profiles { user: tx-sender }
                    (merge profile { 
                        total-earnings: (+ (get total-earnings profile) reward-amount),
                        reputation: (+ (get reputation profile) u1)
                    }))
            )
            
            (ok reward-amount)
        )
    )
)

(define-public (mint-video-clip (video-id uint) (title (string-ascii 100)) (start-time uint) (end-time uint))
    (let ((clip-id (var-get next-clip-id))
          (video-data (unwrap! (map-get? videos { video-id: video-id }) err-not-found))
          (rarity-score (+ (get total-views video-data) (* (- end-time start-time) u100))))
        
        (asserts! (is-eq (get status video-data) "active") err-unauthorized)
        (asserts! (< start-time end-time) err-invalid-input)
        (asserts! (<= end-time (get duration video-data)) err-invalid-input)
        
        (try! (nft-mint? video-clip clip-id tx-sender))
        
        (map-set video-clips { clip-id: clip-id }
            {
                video-id: video-id,
                owner: tx-sender,
                title: title,
                start-time: start-time,
                end-time: end-time,
                mint-block: stacks-block-height,
                rarity-score: rarity-score
            }
        )
        
        (var-set next-clip-id (+ clip-id u1))
        (ok clip-id)
    )
)

(define-public (create-dao-proposal (target-video uint) (proposal-type (string-ascii 20)) (description (string-ascii 200)))
    (let ((proposal-id (var-get next-proposal-id))
          (voting-power (calculate-voting-power tx-sender)))
        
        (asserts! (>= voting-power u10) err-unauthorized)
        (asserts! (is-some (map-get? videos { video-id: target-video })) err-not-found)
        
        (map-set dao-proposals { proposal-id: proposal-id }
            {
                proposer: tx-sender,
                target-video: target-video,
                proposal-type: proposal-type,
                description: description,
                votes-for: u0,
                votes-against: u0,
                voting-deadline: (+ stacks-block-height u1440),
                executed: false
            }
        )
        
        (var-set next-proposal-id (+ proposal-id u1))
        (ok proposal-id)
    )
)

(define-public (vote-on-proposal (proposal-id uint) (support bool))
    (let ((proposal (unwrap! (map-get? dao-proposals { proposal-id: proposal-id }) err-not-found))
          (voting-power (calculate-voting-power tx-sender)))
        
        (asserts! (< stacks-block-height (get voting-deadline proposal)) err-voting-ended)
        (asserts! (is-none (map-get? dao-votes { proposal-id: proposal-id, voter: tx-sender })) err-already-exists)
        (asserts! (> voting-power u0) err-unauthorized)
        
        (map-set dao-votes { proposal-id: proposal-id, voter: tx-sender }
            { vote: support, voting-power: voting-power })
        
        (let ((updated-proposal
                (if support
                    (merge proposal { votes-for: (+ (get votes-for proposal) voting-power) })
                    (merge proposal { votes-against: (+ (get votes-against proposal) voting-power) }))))
            (map-set dao-proposals { proposal-id: proposal-id } updated-proposal)
        )
        
        (ok true)
    )
)

(define-public (execute-proposal (proposal-id uint))
    (let ((proposal (unwrap! (map-get? dao-proposals { proposal-id: proposal-id }) err-not-found)))
        
        (asserts! (>= stacks-block-height (get voting-deadline proposal)) err-voting-ended)
        (asserts! (not (get executed proposal)) err-already-exists)
        (asserts! (> (get votes-for proposal) (get votes-against proposal)) err-unauthorized)
        
        (begin
            (if (is-eq (get proposal-type proposal) "remove")
                (let ((video-data (unwrap! (map-get? videos { video-id: (get target-video proposal) }) err-not-found)))
                    (map-set videos { video-id: (get target-video proposal) }
                        (merge video-data { status: "removed" }))
                )
                true
            )
            
            (map-set dao-proposals { proposal-id: proposal-id }
                (merge proposal { executed: true }))
            
            (ok true)
        )
    )
)

(define-public (setup-creator-subscription (subscription-price uint))
    (let ((creator tx-sender))
        (asserts! (> subscription-price u0) err-invalid-input)
        
        (map-set creator-subscriptions { creator: creator }
            {
                subscription-price: subscription-price,
                total-subscribers: u0,
                monthly-revenue: u0,
                active: true
            }
        )
        
        (ok true)
    )
)

(define-public (subscribe-to-creator (creator principal))
    (let ((subscription-data (unwrap! (map-get? creator-subscriptions { creator: creator }) err-not-found))
          (subscriber tx-sender)
          (subscription-price (get subscription-price subscription-data))
          (expiry-block (+ stacks-block-height u4320)))
        
        (asserts! (get active subscription-data) err-unauthorized)
        (asserts! (>= (ft-get-balance tub3-token subscriber) subscription-price) err-insufficient-funds)
        (asserts! (is-none (map-get? user-subscriptions { subscriber: subscriber, creator: creator })) err-already-exists)
        
        (try! (process-subscription-payment subscriber creator subscription-price))
        
        (map-set user-subscriptions { subscriber: subscriber, creator: creator }
            {
                start-block: stacks-block-height,
                expiry-block: expiry-block,
                monthly-payment: subscription-price,
                auto-renew: false
            }
        )
        
        (map-set creator-subscriptions { creator: creator }
            (merge subscription-data { 
                total-subscribers: (+ (get total-subscribers subscription-data) u1),
                monthly-revenue: (+ (get monthly-revenue subscription-data) subscription-price)
            }))
        
        (ok true)
    )
)

(define-public (renew-subscription (creator principal))
    (let ((subscription (unwrap! (map-get? user-subscriptions { subscriber: tx-sender, creator: creator }) err-subscription-not-found))
          (creator-data (unwrap! (map-get? creator-subscriptions { creator: creator }) err-not-found))
          (subscription-price (get monthly-payment subscription))
          (new-expiry (+ (get expiry-block subscription) u4320)))
        
        (asserts! (get active creator-data) err-unauthorized)
        (asserts! (>= (ft-get-balance tub3-token tx-sender) subscription-price) err-insufficient-funds)
        
        (try! (process-subscription-payment tx-sender creator subscription-price))
        
        (map-set user-subscriptions { subscriber: tx-sender, creator: creator }
            (merge subscription { expiry-block: new-expiry }))
        
        (map-set creator-subscriptions { creator: creator }
            (merge creator-data { 
                monthly-revenue: (+ (get monthly-revenue creator-data) subscription-price)
            }))
        
        (ok true)
    )
)

(define-public (cancel-subscription (creator principal))
    (let ((subscription (unwrap! (map-get? user-subscriptions { subscriber: tx-sender, creator: creator }) err-subscription-not-found))
          (creator-data (unwrap! (map-get? creator-subscriptions { creator: creator }) err-not-found)))
        
        (map-delete user-subscriptions { subscriber: tx-sender, creator: creator })
        
        (map-set creator-subscriptions { creator: creator }
            (merge creator-data { 
                total-subscribers: (- (get total-subscribers creator-data) u1)
            }))
        
        (ok true)
    )
)

(define-public (upload-exclusive-video (title (string-ascii 100)) (ipfs-hash (string-ascii 100)) (duration uint))
    (let ((video-id (var-get next-video-id))
          (creator tx-sender))
        (asserts! (> (len title) u0) err-invalid-input)
        (asserts! (> (len ipfs-hash) u0) err-invalid-input)
        (asserts! (> duration u0) err-invalid-input)
        (asserts! (is-some (map-get? creator-subscriptions { creator: creator })) err-unauthorized)
        
        (map-set videos { video-id: video-id }
            {
                creator: creator,
                title: title,
                ipfs-hash: ipfs-hash,
                duration: duration,
                upload-block: stacks-block-height,
                total-views: u0,
                total-revenue: u0,
                status: "subscriber-only"
            }
        )
        
        (let ((profile (default-to 
                { username: "", reputation: u100, total-earnings: u0, videos-created: u0, videos-watched: u0 }
                (map-get? user-profiles { user: creator }))))
            (map-set user-profiles { user: creator }
                (merge profile { videos-created: (+ (get videos-created profile) u1) }))
        )
        
        (var-set next-video-id (+ video-id u1))
        (ok video-id)
    )
)

(define-public (watch-exclusive-video (video-id uint) (watch-duration uint))
    (let ((video-data (unwrap! (map-get? videos { video-id: video-id }) err-not-found))
          (viewer tx-sender)
          (creator (get creator video-data))
          (completion-rate (/ (* watch-duration u100) (get duration video-data))))
        
        (asserts! (is-eq (get status video-data) "subscriber-only") err-unauthorized)
        (asserts! (> watch-duration u0) err-invalid-input)
        (asserts! (is-subscription-active viewer creator) err-subscription-expired)
        
        (map-set watch-sessions { video-id: video-id, viewer: viewer }
            {
                watch-time: watch-duration,
                completion-rate: completion-rate,
                last-watch-block: stacks-block-height,
                reward-claimed: false
            }
        )
        
        (map-set videos { video-id: video-id }
            (merge video-data { total-views: (+ (get total-views video-data) u1) }))
        
        (let ((profile (default-to 
                { username: "", reputation: u100, total-earnings: u0, videos-created: u0, videos-watched: u0 }
                (map-get? user-profiles { user: viewer }))))
            (map-set user-profiles { user: viewer }
                (merge profile { videos-watched: (+ (get videos-watched profile) u1) }))
        )
        
        (ok completion-rate)
    )
)

(define-read-only (get-video (video-id uint))
    (map-get? videos { video-id: video-id })
)

(define-read-only (get-user-profile (user principal))
    (map-get? user-profiles { user: user })
)

(define-read-only (get-video-clip (clip-id uint))
    (map-get? video-clips { clip-id: clip-id })
)

(define-read-only (get-watch-session (video-id uint) (viewer principal))
    (map-get? watch-sessions { video-id: video-id, viewer: viewer })
)

(define-read-only (get-dao-proposal (proposal-id uint))
    (map-get? dao-proposals { proposal-id: proposal-id })
)

(define-read-only (get-user-vote (proposal-id uint) (voter principal))
    (map-get? dao-votes { proposal-id: proposal-id, voter: voter })
)

(define-read-only (get-total-supply)
    (ft-get-supply tub3-token)
)

(define-read-only (get-balance (user principal))
    (ft-get-balance tub3-token user)
)

(define-read-only (get-creator-subscription (creator principal))
    (map-get? creator-subscriptions { creator: creator })
)

(define-read-only (get-user-subscription (subscriber principal) (creator principal))
    (map-get? user-subscriptions { subscriber: subscriber, creator: creator })
)

(define-read-only (check-subscription-status (subscriber principal) (creator principal))
    (is-subscription-active subscriber creator)
)

(define-map video-bookmarks { user: principal, video-id: uint } { bookmarked-at: uint })

(define-public (bookmark-video (video-id uint))
  (let ((user tx-sender))
    (asserts! (is-some (map-get? videos { video-id: video-id })) err-not-found)
    (asserts! (is-none (map-get? video-bookmarks { user: user, video-id: video-id })) err-already-exists)
    (ok (map-set video-bookmarks { user: user, video-id: video-id } { bookmarked-at: stacks-block-height }))
  )
)

(define-public (remove-bookmark (video-id uint))
  (let ((user tx-sender))
    (asserts! (is-some (map-get? video-bookmarks { user: user, video-id: video-id })) err-not-found)
    (ok (map-delete video-bookmarks { user: user, video-id: video-id }))
  )
)

(define-read-only (is-video-bookmarked (user principal) (video-id uint))
  (is-some (map-get? video-bookmarks { user: user, video-id: video-id }))
)
