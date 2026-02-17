# Invariants
echidna-x-silo:
	echidna x-silo/test/echidna/XSiloTester.t.sol --contract XSiloTester --config ./x-silo/test/echidna/_config/echidna_config.yaml --corpus-dir ./x-silo/test/echidna/_corpus/echidna/default/_data/corpus/x-silo

echidna-leverage:
	echidna silo-core/test/echidna-leverage/LeverageTester.t.sol --contract LeverageTester --config ./silo-core/test/echidna-leverage/_config/echidna_config.yaml --corpus-dir ./silo-core/test/echidna-leverage/_corpus/echidna/default/_data/corpus

echidna-leverage-assert:
	echidna silo-core/test/echidna-leverage/LeverageTester.t.sol --contract LeverageTester --test-mode assertion --config ./silo-core/test/echidna-leverage/_config/echidna_config.yaml --corpus-dir ./silo-core/test/echidna-leverage/_corpus/echidna/default/_data/corpus

echidna-hook-v2:
	echidna silo-core/test/echidna-defaulting/siloHookV2/DefaultingTester.t.sol --contract DefaultingTester --config ./silo-core/test/echidna-defaulting/siloHookV2/_config/echidna_config.yaml --corpus-dir ./silo-core/test/echidna-defaulting/siloHookV2/_corpus/echidna/default/_data/corpus

echidna-hook-v2-assert:
	echidna silo-core/test/echidna-defaulting/siloHookV2/DefaultingTester.t.sol --contract DefaultingTester --test-mode assertion --config ./silo-core/test/echidna-defaulting/siloHookV2/_config/echidna_config.yaml --corpus-dir ./silo-core/test/echidna-defaulting/siloHookV2/_corpus/echidna/default/_data/corpus

echidna-hook-v3:
	echidna silo-core/test/echidna-defaulting/siloHookV3/HookV3Tester.t.sol --contract HookV3Tester --config ./silo-core/test/echidna-defaulting/siloHookV3/_config/echidna_config.yaml --corpus-dir ./silo-core/test/echidna-defaulting/siloHookV3/_corpus/echidna/default/_data/corpus

echidna-hook-v3-assert:
	echidna silo-core/test/echidna-defaulting/siloHookV3/HookV3Tester.t.sol --contract HookV3Tester --test-mode assertion --config ./silo-core/test/echidna-defaulting/siloHookV3/_config/echidna_config.yaml --corpus-dir ./silo-core/test/echidna-defaulting/siloHookV3/_corpus/echidna/default/_data/corpus

echidna:
	echidna silo-core/test/invariants/Tester.t.sol --contract Tester --config ./silo-core/test/invariants/_config/echidna_config.yaml --corpus-dir ./silo-core/test/invariants/_corpus/echidna/default/_data/corpus

echidna-assert:
	echidna silo-core/test/invariants/Tester.t.sol --contract Tester --test-mode assertion --config ./silo-core/test/invariants/_config/echidna_config.yaml --corpus-dir ./silo-core/test/invariants/_corpus/echidna/default/_data/corpus

echidna-explore:
	echidna silo-core/test/invariants/Tester.t.sol --contract Tester --test-mode exploration --config ./silo-core/test/invariants/_config/echidna_config.yaml --corpus-dir ./silo-core/test/invariants/_corpus/echidna/default/_data/corpus


# Medusa
medusa:
	medusa fuzz --config ./medusa.json
